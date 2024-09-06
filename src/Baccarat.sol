// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Baccarat is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    enum BetType { Player, Banker, Tie }
    enum GameResult { PlayerWin, BankerWin, Tie }
    enum BaccaratStateMachine { Bet, Resolve, ClaimPlayer, ClaimOwner }

    struct Bet {
        address player;
        BetType betType;
        uint256 amount;
        bool resolved;
    }

    struct Hand {
        uint8[] cards;
        uint8 score;
    }

    uint256 public minBet;
    uint256 public maxBet;
    uint256 public houseEdge; // fee percentage
    uint256 public checkPoint; // for Random
	uint256 public nonce; // for Random
    uint256 public totalBetAmount; // Total bet amount in the current game
    uint256 public feeAmount; // Total fee collected
    uint256 public claimedPlayers; // Track the number of players who have claimed
    mapping(address => Bet) public activeBets;
    mapping(address => uint256) public playerRewards;
    address[] public players;
    address[] public winners;

    BaccaratStateMachine public currentState = BaccaratStateMachine.Bet;

	bool isStopped = false; // for emergency stop

    event BetPlaced(address indexed player, uint256 amount, BetType betType);
    event BetResolved(address indexed player, BetType betType, GameResult result, uint256 payout);
    event GameResultEvent(
        uint8[] playerCards,
        uint8[] bankerCards,
        uint8 playerScore,
        uint8 bankerScore,
        GameResult result
    );

    modifier bettingPhase() {
        require(currentState == BaccaratStateMachine.Bet, "Not in Betting Phase");
        _;
    }

    modifier resolvePhase() {
        require(currentState == BaccaratStateMachine.Resolve, "Not in Resolve Phase");
        _;
    }

    modifier claimPlayerPhase() {
        require(currentState == BaccaratStateMachine.ClaimPlayer, "Not in Claim Player Phase");
        _;
    }

    modifier claimOwnerPhase() {
        require(currentState == BaccaratStateMachine.ClaimOwner, "Not in Claim Owner Phase");
        _;
    }

	modifier stoppedInEmergency{
		require(!isStopped);
		_;
	} 

	modifier onlyWhenStopped {
        require(isStopped);
        _;
    }

	function stopContract() public onlyOwner bettingPhase{
		isStopped = true;
	}

	function resumeContract() public onlyOwner{
		isStopped = false;
	}

    function initialize(uint256 _minBet, uint256 _maxBet, uint256 _houseEdge) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        minBet = _minBet;
        maxBet = _maxBet;
        houseEdge = _houseEdge;
    }

    function placeBet(BetType _betType) external payable bettingPhase stoppedInEmergency {
        require(msg.value == 0.001 ether, "Bet amount must be exactly 0.001 ether");
        require(activeBets[msg.sender].amount == 0, "Active bet already exists");

        activeBets[msg.sender] = Bet({
            player: msg.sender,
            betType: _betType,
            amount: msg.value,
            resolved: false
        });
        players.push(msg.sender);

        totalBetAmount += msg.value;

        if (players.length == 5) {
            currentState = BaccaratStateMachine.Resolve;
            checkPoint = block.number + 1;
        }

        emit BetPlaced(msg.sender, msg.value, _betType);
    }

    function resolveBets() external resolvePhase {
        require(checkPoint < block.number, "Please wait until the next block");

        (Hand memory playerHand, Hand memory bankerHand) = _dealCards();
        GameResult gameResult = _determineOutcome(playerHand, bankerHand);

        emit GameResultEvent(
            playerHand.cards,
            bankerHand.cards,
            playerHand.score,
            bankerHand.score,
            gameResult
        );

        uint256 winnerCount = 0;
        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            Bet storage bet = activeBets[playerAddress];

            if (!bet.resolved) {
                if ((bet.betType == BetType.Player && gameResult == GameResult.PlayerWin) ||
                    (bet.betType == BetType.Banker && gameResult == GameResult.BankerWin) ||
                    (bet.betType == BetType.Tie && gameResult == GameResult.Tie)) {
                    winners.push(playerAddress);
                    winnerCount++;
                }
                bet.resolved = true;
            }
        }

        if (winnerCount > 0) {
            // If there are winners, distribute rewards after deducting fee
            feeAmount += 0.0001 ether;  // Owner fee
            uint256 totalReward = totalBetAmount - 0.0001 ether;
            uint256 rewardPerWinner = totalReward / winnerCount;

            for (uint256 j = 0; j < winners.length; j++) {
                playerRewards[winners[j]] += rewardPerWinner;
                emit BetResolved(winners[j], activeBets[winners[j]].betType, gameResult, rewardPerWinner);
            }
            currentState = BaccaratStateMachine.ClaimPlayer;
        } else {
            // No winners, owner claims all
            feeAmount += totalBetAmount;
            currentState = BaccaratStateMachine.ClaimOwner;
        }

        delete players;
        totalBetAmount = 0;
        claimedPlayers = 0; // Reset claimed players count for the next round
    }

    function claimReward() external claimPlayerPhase {
        require(playerRewards[msg.sender] > 0, "No rewards to claim");
        uint256 reward = playerRewards[msg.sender];
        playerRewards[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: reward}("");
		require(success, "Error: claimReward");

        claimedPlayers++;
        if (claimedPlayers == winners.length) {
            currentState = BaccaratStateMachine.ClaimOwner;
        }
    }

    function claimFee() external onlyOwner claimOwnerPhase {
        require(feeAmount > 0, "No fee to claim");
        uint256 amountToClaim = feeAmount;
        feeAmount = 0;
        (bool success, ) = payable(owner()).call{value: amountToClaim}("");
		require(success, "Error: claimFee");

        currentState = BaccaratStateMachine.Bet; // Reset to betting phase after claiming
    }

	function getWinnersCount() external returns(uint256){
		return winners.length;
	}

    function _dealCards() internal returns (Hand memory playerHand, Hand memory bankerHand) {
        playerHand.cards = _multicallDrawCard(2);
        bankerHand.cards = _multicallDrawCard(2);

        playerHand.score = _calculateScore(playerHand.cards);
        bankerHand.score = _calculateScore(bankerHand.cards);

        if (playerHand.score <= 5) {
            uint8[] memory newPlayerCards = new uint8[](playerHand.cards.length + 1);
            for (uint8 i = 0; i < playerHand.cards.length; i++) {
                newPlayerCards[i] = playerHand.cards[i];
            }
            newPlayerCards[playerHand.cards.length] = _multicallDrawCard(1)[0];
            playerHand.cards = newPlayerCards;
            playerHand.score = _calculateScore(playerHand.cards);
        }

        if (bankerHand.score < 3 || 
            (bankerHand.score == 3 && playerHand.cards.length == 3 && playerHand.cards[2] != 8) ||
            (bankerHand.score == 4 && playerHand.cards.length == 3 && (playerHand.cards[2] >= 2 && playerHand.cards[2] <= 7)) ||
            (bankerHand.score == 5 && playerHand.cards.length == 3 && (playerHand.cards[2] >= 4 && playerHand.cards[2] <= 7)) ||
            (bankerHand.score == 6 && playerHand.cards.length == 3 && (playerHand.cards[2] == 6 || playerHand.cards[2] == 7))) {

            uint8[] memory newBankerCards = new uint8[](bankerHand.cards.length + 1);
            for (uint8 i = 0; i < bankerHand.cards.length; i++) {
                newBankerCards[i] = bankerHand.cards[i];
            }
            newBankerCards[bankerHand.cards.length] = _multicallDrawCard(1)[0];
            bankerHand.cards = newBankerCards;
            bankerHand.score = _calculateScore(bankerHand.cards);
        }

        return (playerHand, bankerHand);
    }

    function _drawCard() internal returns (uint8) {
        uint8 card = uint8(uint256(keccak256(abi.encodePacked(blockhash(checkPoint), nonce)))) % 13 + 1;
		nonce++;
        if (card > 10) card = 0; // Face cards are worth 0 points
        return card;
    }

    function _multicallDrawCard(uint8 numCards) internal returns (uint8[] memory) {
        uint8[] memory cards = new uint8[](numCards);
        for (uint8 i = 0; i < numCards; i++) {
            cards[i] = _drawCard();
        }
        return cards;
    }

    function _calculateScore(uint8[] memory cards) internal pure returns (uint8) {
        uint8 score = 0;
        for (uint8 i = 0; i < cards.length; i++) {
            score = (score + cards[i]) % 10;
        }
        return score;
    }

    function _determineOutcome(Hand memory playerHand, Hand memory bankerHand) internal pure returns (GameResult) {
        if (playerHand.score > bankerHand.score) {
            return GameResult.PlayerWin;
        } else if (bankerHand.score > playerHand.score) {
            return GameResult.BankerWin;
        } else {
            return GameResult.Tie;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner onlyWhenStopped {}

	function emergencyWithdraw() public onlyWhenStopped onlyOwner{
		(bool success, ) = payable(owner()).call{value: address(this).balance}("");
		require(success, "Error: emergencyWithdraw");
	}
}

