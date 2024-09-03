// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Baccarat is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    enum BetType { Player, Banker, Tie }
    enum GameResult { PlayerWin, BankerWin, Tie }

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
    uint256 public houseEdge;
    mapping(address => Bet) public activeBets;
    address[] public players;

    event BetPlaced(address indexed player, uint256 amount, BetType betType);
    event BetResolved(address indexed player, BetType betType, GameResult result, uint256 payout);
    event GameResultEvent(
        uint8[] playerCards,
        uint8[] bankerCards,
        uint8 playerScore,
        uint8 bankerScore,
        GameResult result
    );

    function initialize(uint256 _minBet, uint256 _maxBet, uint256 _houseEdge) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        minBet = _minBet;
        maxBet = _maxBet;
        houseEdge = _houseEdge;
    }

    function placeBet(BetType _betType) external payable {
        require(msg.value >= minBet && msg.value <= maxBet, "Bet amount out of range");
        require(activeBets[msg.sender].amount == 0, "Active bet already exists");

        activeBets[msg.sender] = Bet({
            player: msg.sender,
            betType: _betType,
            amount: msg.value,
            resolved: false
        });
        players.push(msg.sender);

        emit BetPlaced(msg.sender, msg.value, _betType);
    }

    function resolveBets() external onlyOwner {
        require(players.length > 0, "No active bets");

        (Hand memory playerHand, Hand memory bankerHand) = _dealCards();
        GameResult gameResult = _determineOutcome(playerHand, bankerHand);

        // Emit the game result event with detailed information
        emit GameResultEvent(
            playerHand.cards,
            bankerHand.cards,
            playerHand.score,
            bankerHand.score,
            gameResult
        );

        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            Bet storage bet = activeBets[playerAddress];

            if (!bet.resolved) {
                uint256 payout = calculatePayout(bet.amount, bet.betType, gameResult);
                if (payout > 0) {
                    payable(bet.player).transfer(payout);
                }

                bet.resolved = true;
                emit BetResolved(bet.player, bet.betType, gameResult, payout);
            }
        }

        delete players; // Reset players array for the next round
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

    function _drawCard() internal view returns (uint8) {
        uint8 card = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % 13) + 1;
        if (card > 10) card = 0; // Face cards are worth 0 points
        return card;
    }

    function _multicallDrawCard(uint8 numCards) internal view returns (uint8[] memory) {
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

    function calculatePayout(uint256 amount, BetType betType, GameResult gameResult) internal view returns (uint256) {
        if ((betType == BetType.Player && gameResult == GameResult.PlayerWin) ||
            (betType == BetType.Banker && gameResult == GameResult.BankerWin) ||
            (betType == BetType.Tie && gameResult == GameResult.Tie)) {
            uint256 payout = amount * getMultiplier(betType) * (100 - houseEdge) / 100;
            return payout;
        }
        return 0;
    }

    function getMultiplier(BetType betType) internal pure returns (uint256) {
        if (betType == BetType.Player) {
            return 2; // 1:1 payout
        } else if (betType == BetType.Banker) {
            return 2; // 1:1 payout, typically minus a commission
        } else if (betType == BetType.Tie) {
            return 9; // 8:1 payout
        }
        return 0;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

