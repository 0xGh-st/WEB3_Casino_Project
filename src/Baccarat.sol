// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IGameChainManager.sol";

contract Baccarat is AccessControlEnumerableUpgradeable {
    
    uint256 public constant SUPER6_BANKER = 0;
    uint256 public constant PLAYER_BET = 1;
    uint256 public constant BANKER_BET = 2;
    uint256 public constant TIE_BET = 3;
    uint256 public constant P_PAIR_BET = 4;
    uint256 public constant B_PAIR_BET = 5;
    uint256 public constant SUPER6_BET = 6;
    uint256 public constant EGALITE_BET = 7;
    uint256 public constant PERFECT_PAIR_BET = 17;
    uint256 public constant MAX_BET_INDEX = 18;

    uint256 public constant CARD_NUMBER = 52;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event BetRateUpdated(uint256 betType, uint256 rate);
    event NumMaxBetsUpdated(uint256 value);
    event MaxTotalBetsUpdated(uint256 tableId, uint256 value);
    event MaxBetsUpdated(uint256 tableId, uint256[] types, uint256[] values);
    event MaxBetsReset(uint256 tableId);
    event RoundTimeUpdated(uint256 time);
    event TableCreated(uint256 tableId);
    event TableDisabled(uint256 tableId);
    event TableEnabled(uint256 tableId);

    event RoundStarted(uint256 tableId, uint256 roundId, bytes32 secretHash);
    event BetPlaced(uint256 tableId, uint256 roundId, bytes32 seedHash, address account, uint256[] types, uint256[] amounts);
    event RoundEnded(uint256 tableId, uint256 roundId, uint256 secretValue);
    event RewardDistributed(uint256 tableId, uint256 roundId, address account, uint256 amount, uint256 reward, uint256 betType, uint256 betIndex);
    event RefundDistributed(uint256 tableId, uint256 roundId, address account, uint256 amount, uint256 betType, uint256 betIndex);

    struct Round {
        bytes32 random;
        bytes32 secretHash;
        uint256 secretValue;
        uint256 numBets;
        bool closed;
        uint256 startAt;
        uint256 maxBet;
        uint256 total;
    }

    struct Bet {
        uint256[] types;
        uint256[] amounts;
        bytes32[] seedHashes;
    }

    IERC20 public token;

    // table id => current round id
    mapping(uint256 => uint256) private _currentRound;

    // table id => round id => round information
    mapping(uint256 => mapping(uint256 => Round)) public rounds;

    // table id => round id => participants
    mapping(uint256 => mapping(uint256 => address[])) private _participants;

    // table id => round id => user address => bet information
    mapping(uint256 => mapping(uint256 => mapping(address => Bet))) private _bets;

    // table id => round id => user address => bet type => bet amount
    mapping(uint256 => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) private _betAmounts;

    // table id => round id => betType => max bet of round
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) public maxBets;

    // table id => maxTotalBet
    mapping(uint256 => uint256) private _maxTotalBets;

    // bet type => rate
    mapping(uint256 => uint256) public betRates;

    // Now, it is unused but can't delete because smart contract is deployed by proxy
    uint256 public minBalance;

    uint256 public numMaxBets;

    uint256[] private _activeTables;

    uint256[] private _inactiveTables;

    mapping(uint256 => uint256) private _activeTableIndexs;
    mapping(uint256 => uint256) private _inactiveTableIndexs;

    uint256 private _tableCount;

    uint256 public roundTime;

    IGameChainManager public gameManager;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Baccarat: caller is not admin");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Baccarat: caller is not operator");
        _;
    }

    function initialize(IERC20 _token, IGameChainManager _gameManager)
        external
        initializer
    {
        __AccessControlEnumerable_init();

        token = _token;
        gameManager = _gameManager;

        address msgSender = _msgSender();

        _setupRole(DEFAULT_ADMIN_ROLE, msgSender);
        _setupRole(OPERATOR_ROLE, msgSender);

        numMaxBets = 5000;
        roundTime = 1 minutes;

        _maxTotalBets[0] = 1000000000;

        // Global default max bets
        maxBets[0][0][TIE_BET] = 100000000;  
        maxBets[0][0][P_PAIR_BET] = 100000000;
        maxBets[0][0][B_PAIR_BET] = 100000000;
        maxBets[0][0][PERFECT_PAIR_BET] = 25000000;
        maxBets[0][0][SUPER6_BET] = 100000000;
        maxBets[0][0][EGALITE_BET] = 10000000;
        maxBets[0][0][EGALITE_BET + 1] = 10000000;
        maxBets[0][0][EGALITE_BET + 2] = 10000000;
        maxBets[0][0][EGALITE_BET + 3] = 10000000;
        maxBets[0][0][EGALITE_BET + 4] = 10000000;
        maxBets[0][0][EGALITE_BET + 5] = 10000000;
        maxBets[0][0][EGALITE_BET + 6] = 10000000;
        maxBets[0][0][EGALITE_BET + 7] = 10000000;
        maxBets[0][0][EGALITE_BET + 8] = 10000000;
        maxBets[0][0][EGALITE_BET + 9] = 10000000;

        // Bet Rates
        betRates[PLAYER_BET] = 100;         // 1
        betRates[BANKER_BET] = 100;         // 1
        betRates[TIE_BET] = 800;            // 8
        betRates[P_PAIR_BET] = 1100;        // 11
        betRates[B_PAIR_BET] = 1100;        // 11
        betRates[PERFECT_PAIR_BET] = 2500;  // 25
        betRates[SUPER6_BANKER] = 50;       // 0.5
        betRates[SUPER6_BET] = 1200;        // 12
        betRates[EGALITE_BET] = 15000;      // 150
        betRates[EGALITE_BET + 1] = 21500;  // 215
        betRates[EGALITE_BET + 2] = 22000;  // 220
        betRates[EGALITE_BET + 3] = 20000;  // 200
        betRates[EGALITE_BET + 4] = 12000;  // 120
        betRates[EGALITE_BET + 5] = 11000;  // 110
        betRates[EGALITE_BET + 6] = 4500;   // 45
        betRates[EGALITE_BET + 7] = 4500;   // 45
        betRates[EGALITE_BET + 8] = 8000;   // 80
        betRates[EGALITE_BET + 9] = 8000;   // 80

        _activeTables.push(0);
        _inactiveTables.push(0);
    }

    function setGameManager(IGameChainManager _gameManager)
        external
        onlyAdmin
    {
        gameManager = _gameManager;
    }

    function setBetRate(uint256 betType, uint256 rate)
        external
        onlyOperator
    {
        betRates[betType] = rate;

        emit BetRateUpdated(betType, rate);
    }

    function setNumMaxBets(uint256 value)
        external
        onlyOperator

    {
        numMaxBets = value;

        emit NumMaxBetsUpdated(value);
    }

    function setMaxTotal(uint256 tableId, uint256 value)
        external
        onlyOperator
    {
        require (tableId > 0 && tableId <= _tableCount, "Baccarat: inavlid tableId");

        _maxTotalBets[tableId] = value;

        emit MaxTotalBetsUpdated(tableId, value);
    }

    function setDefaultMaxTotal(uint256 value)
        external
        onlyOperator
    {
        _maxTotalBets[0] = value;

        emit MaxTotalBetsUpdated(0, value);
    }

    function setMaxBets(uint256 tableId, uint256[] memory types, uint256[] memory values)
        external
        onlyOperator
    {
        for(uint256 i = 0; i < types.length; i++) {
            maxBets[tableId][0][types[i]] = values[i];
        }

        emit MaxBetsUpdated(tableId, types, values);
    }

    function resetDefaultMaxBets(uint256 tableId)
        external
        onlyOperator
    {
        for (uint256 i = 1; i < MAX_BET_INDEX; i++) {
            maxBets[tableId][0][i] = maxBets[0][0][i];
        }

        emit MaxBetsReset(tableId);
    }

    function setRoundTime(uint256 time)
        external
        onlyOperator
    {
        roundTime = time;

        emit RoundTimeUpdated(time);
    }

    function getCurrentRound(uint256 tableId)
        public
        view
        returns (uint256)
    {
        return _currentRound[tableId] + 1;
    }

    function getTotalParticipants(uint256 tableId, uint256 roundId)
        external
        view
        returns (uint256)
    {
        return _participants[tableId][roundId].length;
    }

    function getParticipants(uint256 tableId, uint256 roundId)
        external
        view
        returns (address[] memory)
    {
        return _participants[tableId][roundId];
    }

    function getBets(uint256 tableId, uint256 roundId, address account)
        external
        view
        returns (uint256[] memory, uint256[] memory, bytes32[] memory)
    {
        Bet memory bet = _bets[tableId][roundId][account];

        return (bet.types, bet.amounts, bet.seedHashes);
    }

    function getMaxTotalBets(uint256 tableId) 
        external
        view
        returns (uint256)
    {
        return _maxTotalBets[tableId];
    }

    function getHash(uint256 value)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(value));
    }

    function createTable()
        external
        onlyOperator
    {
        uint256 id = ++_tableCount;

        _activeTableIndexs[id] = _activeTables.length;

        _activeTables.push(id);

        _maxTotalBets[id] = _maxTotalBets[0];

        for (uint256 i = 1; i < MAX_BET_INDEX; i++) {
            maxBets[id][0][i] = maxBets[0][0][i];
        }

        emit TableCreated(id);

        gameManager.refillETH(_msgSender());
    }

    function enableTable(uint256 tableId)
        external
        onlyOperator
    {
        uint256 index = _inactiveTableIndexs[tableId];

        require(_activeTableIndexs[tableId] == 0 && index != 0, "Baccarat: table id is invalid");

        _inactiveTableIndexs[tableId] = 0;

        _inactiveTables[index] = _inactiveTables[_inactiveTables.length - 1];
        _inactiveTables.pop();

        _activeTableIndexs[tableId] = _activeTables.length;

        _activeTables.push(tableId);

        emit TableEnabled(tableId);

        gameManager.refillETH(_msgSender());
    }

    function disableTable(uint256 tableId)
        external
        onlyOperator
    {
        uint256 index = _activeTableIndexs[tableId];

        require(_inactiveTableIndexs[tableId] == 0 && index != 0, "Baccarat: table id is invalid");

        _activeTableIndexs[tableId] = 0;

        _activeTables[index] = _activeTables[_activeTables.length - 1];
        _activeTables.pop();

        _inactiveTableIndexs[tableId] = _inactiveTables.length;

        _inactiveTables.push(tableId);

        emit TableDisabled(tableId);

        gameManager.refillETH(_msgSender());
    }

    function getActiveTables()
        external
        view
        returns (uint256[] memory)
    {
        return _activeTables;
    }

    function getInactiveTables()
        external
        view
        returns (uint256[] memory)
    {
        return _inactiveTables;
    }

    function startRound(uint256 tableId, uint256 currentSecretValue, bytes32 nextSecretHash)
        external
        onlyOperator
    {
        uint256 roundId;

        if (currentSecretValue != 0) {
            roundId = getCurrentRound(tableId);

            Round storage round = rounds[tableId][roundId];

            require(block.timestamp >= round.startAt + roundTime, "Baccarat: round is running");

            bytes32 secretHash = round.secretHash;

            require(secretHash != 0 && secretHash == getHash(currentSecretValue), "Baccarat: secret value is invalid");

            round.random ^= getHash(uint256(secretHash) ^ currentSecretValue ^ block.timestamp);
            round.secretValue = currentSecretValue;
            round.closed = true;

            _distributeReward(tableId, roundId);

            _currentRound[tableId]++;

            emit RoundEnded(tableId, roundId, currentSecretValue);
        }

        if (_activeTableIndexs[tableId] == 0) {
            return;
        }

        require(nextSecretHash != 0, "Baccarat: secret hash is invalid");

        roundId = getCurrentRound(tableId);

        require(rounds[tableId][roundId].secretHash == 0, "Baccarat: round was started");

        rounds[tableId][roundId] = Round(0, nextSecretHash, 0, 0, false, block.timestamp, _maxTotalBets[tableId], 0);

        for (uint256 i = 1; i < MAX_BET_INDEX; i++) {
            maxBets[tableId][roundId][i] = maxBets[tableId][0][i];
        }

        emit RoundStarted(tableId, roundId, nextSecretHash);

        gameManager.refillETH(_msgSender());
    }

    function placeBet(uint256 tableId, bytes32 seedHash, uint256[] memory types, uint256[] memory amounts)
        external
    {
        require(seedHash != 0, "Baccarat: seed hash is invalid");

        uint256 length = types.length;

        require(length > 0 && length == amounts.length, "Baccarat: length of arrays is invalid");

        uint256 roundId = getCurrentRound(tableId);

        Round storage round = rounds[tableId][roundId];

        require(round.secretHash != 0, "Baccarat: round is not started yet");

        require(block.timestamp <= round.startAt + roundTime, "Baccarat: round end");

        require(round.numBets + length <= numMaxBets, "Baccarat: number of bets reach maximum");

        round.random ^= keccak256(abi.encodePacked(seedHash, types, amounts));

        round.numBets += length;

        address msgSender = _msgSender();

        Bet storage bet = _bets[tableId][roundId][msgSender];

        if (bet.types.length == 0) {
            _participants[tableId][roundId].push(msgSender);
        }

        bet.seedHashes.push(seedHash);

        uint256 total;

        for (uint256 i = 0; i < length; i++) {
            uint256 maxBetAllowed = maxBets[tableId][roundId][types[i]];
            uint256 currentBet = _betAmounts[tableId][roundId][msgSender][types[i]];

            require(amounts[i] > 0, "Baccarat: amount is invalid");
            require(types[i] > 0 && types[i] < MAX_BET_INDEX, "Baccarat: bet type is invalid");
            require(betRates[types[i]] > 0, "Baccarat: bet type is invalid");
            require(round.total + amounts[i] <= round.maxBet, "Baccarat: total exceeds maximum");
            require(maxBetAllowed == 0 || amounts[i] <= maxBetAllowed , "Baccarat: bet exceeds maximum");
            require(currentBet == 0, "Baccarat: bet for this bet type existing" );

            bet.types.push(types[i]);
            bet.amounts.push(amounts[i]);
            _betAmounts[tableId][roundId][msgSender][types[i]] = amounts[i];

            total += amounts[i];
            round.total += amounts[i];
        }

        token.transferFrom(msgSender, address(gameManager), total);

        emit BetPlaced(tableId, roundId, seedHash, msgSender, types, amounts);

        gameManager.refillETH(msgSender);
    }

    function _distributeReward(uint256 tableId, uint256 roundId)
        private
    {
        (,, uint256 result, uint256[] memory betsResult) = getResult(tableId, roundId);

        if (result != 0) {
            uint256 totalReward = 0;

            address[] memory players = _participants[tableId][roundId];

            uint256 numPlayers = players.length;

            for (uint256 i = 0; i < numPlayers; i++) {
                Bet memory bet = _bets[tableId][roundId][players[i]];

                uint256 numBets = bet.types.length;

                for (uint256 j = 0; j < numBets; j++) {
                    uint256 betType = bet.types[j];
                    uint256 amount = bet.amounts[j];
                    bool isRefund = (betsResult[TIE_BET] == 1 && (betType == BANKER_BET || betType == PLAYER_BET));
                    
                    if (betsResult[betType] != 1 && !isRefund) {
                        continue;
                    }

                    uint256 reward = (amount * betRates[betType]) / 100 + amount;
                    if (isRefund) {
                        reward = amount;
                    }
                    // remove super6 due to super6 = true always
                    if (betType == BANKER_BET && betsResult[SUPER6_BET] == 1) {
                        reward = (amount * betRates[SUPER6_BANKER]) / 100 + amount;
                    }

                    gameManager.transferToken(players[i], reward);

                    if (isRefund) {
                        emit RefundDistributed(tableId, roundId, players[i], amount, betType, j);
                    } else {
                        emit RewardDistributed(tableId, roundId, players[i], amount, reward, betType, j);
                    }

                    totalReward += reward;
                }
            }

            uint256 totalBet = rounds[tableId][roundId].total;

            if (totalReward != totalBet) {
                gameManager.updateIncome(tableId, roundId, int256(totalBet) - int256(totalReward));
            }
        }
    }

    function getResult(uint256 tableId, uint256 roundId)
        public
        view
        returns (uint256[] memory cards, uint256[] memory points, uint256 result, uint256[] memory betResults)
    {
        cards = new uint256[](6);
        points = new uint256[](6);
        // there is 17 types of betting currently supported
        betResults = new uint256[](MAX_BET_INDEX);

        Round memory round = rounds[tableId][roundId];

        if (!round.closed) {
            return (cards, points, result, betResults);
        }

        uint256 random = uint256(round.random);

        uint256 cnt = 0;

        // Generates cards
        while (cnt < 6) {
            uint256 card = random % CARD_NUMBER + 1;

            cards[cnt] = card;

            random = uint256(keccak256(abi.encodePacked(random)));

            bool isDuplicated;

            for (uint256 i = 0; i < cnt; i++) {
                if (cards[i] == cards[cnt]) {
                    isDuplicated = true;
                    break;
                }
            }

            if (isDuplicated) {
                continue;
            }

            points[cnt] = card % 13 >= 10 ? 0 : card % 13;

            cnt++;
        }

        // Find possible player pair
        if ((cards[0] % 13) == (cards[2] % 13)) {
            betResults[P_PAIR_BET] = 1;
        }
        if ((cards[1] % 13) == (cards[3] % 13)) {
            betResults[B_PAIR_BET] = 1;
            if (betResults[P_PAIR_BET] == 1) {
                betResults[PERFECT_PAIR_BET] = 1;
            }
        }

        // Calculates player's point in two first cards
        uint256 playerPoint = (points[0] + points[2]) % 10;

        // Calculates banker's point in two first cards
        uint256 bankerPoint = (points[1] + points[3]) % 10;

        // check for natural win (either banker point or player point >= 8)
        bool isNaturalWin = (playerPoint >= 8) || (bankerPoint >= 8);

        if (!isNaturalWin) {
            // Calculates player's point when withdraw third card (only if not Natural Win)
            if (playerPoint < 6) {
                playerPoint = (playerPoint + points[4]) % 10;
            }

            // Calculates banker's point when withdraw third card (only if not Natural Win)
            // 
            // Banker/Player's third card
            // |   | x | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
            // |---|---|---|---|---|---|---|---|---|---|---|---|
            // | 0 | H | H | H | H | H | H | H | H | H | H | H |
            // | 1 | H | H | H | H | H | H | H | H | H | H | H |
            // | 2 | H | H | H | H | H | H | H | H | H | H | H |
            // | 3 | H | H | H | H | H | H | H | H | H | S | H |
            // | 4 | H | S | S | H | H | H | H | H | H | S | S |
            // | 5 | H | S | S | S | S | H | H | H | H | S | S |
            // | 6 | S | S | S | S | S | S | S | H | H | S | S |
            // | 7 | S | S | S | S | S | S | S | S | S | S | S |
            // 
            // H: draw a third card - S: don't draw a third card
            if ((bankerPoint < 3) ||
                (bankerPoint < 6 && playerPoint >= 6 && playerCards[2] == 0) ||
                (bankerPoint == 3 && points[4] != 8) ||
                (bankerPoint == 4 && points[4] >= 2 && points[4] <= 7) ||
                (bankerPoint == 5 && points[4] >= 4 && points[4] <= 7) || 
                (bankerPoint == 6 && points[4] >= 6 && points[4] <= 7))
            {
                bankerPoint = (bankerPoint + points[5]) % 10;
            }
        }

        // Calculates result
        if (playerPoint > bankerPoint) {
            result = PLAYER_BET;

        } else if (playerPoint < bankerPoint) {
            result = BANKER_BET;
            // super6
            if (bankerPoint == 6) {
                betResults[SUPER6_BET] = 1;
            }
        } else {
            result = TIE_BET;
            // Egalite
            uint256 egaliteIdex = EGALITE_BET + bankerPoint;
            betResults[egaliteIdex] = 1;
        }
        betResults[result] = 1;

        return (cards, points, result, betResults);
    }

    function getWinners(uint256 tableId, uint256 roundId)
        external
        view
        returns (address[] memory accounts, uint256[] memory amounts, uint256[] memory indexes)
    {
        (uint256 cnt, address[] memory tmpAccounts, uint256[] memory tmpAmounts, uint256[] memory tmpIndexes) = _getWinners(tableId, roundId);

        accounts = new address[](cnt);
        amounts = new uint256[](cnt);
        indexes = new uint256[](cnt);

        for (uint256 i = 0; i < cnt; i++) {
            accounts[i] = tmpAccounts[i];
            amounts[i] = tmpAmounts[i];
            indexes[i] = tmpIndexes[i];
        }
    }

    function _getWinners(uint256 tableId, uint256 roundId)
        private
        view
        returns (uint256 cnt, address[] memory accounts, uint256[] memory amounts, uint256[] memory indexes)
    {
        uint256 size = rounds[tableId][roundId].numBets;

        accounts = new address[](size);
        amounts = new uint256[](size);
        indexes = new uint256[](size);

        (,,uint256 result,uint256[] memory betsResult) = getResult(tableId, roundId);

        if (result != 0) {
            address[] memory players = _participants[tableId][roundId];

            for (uint256 i = 0; i < players.length; i++) {
                Bet memory bet = _bets[tableId][roundId][players[i]];

                for (uint256 j = 0; j < bet.types.length; j++) {
                    uint256 betType = bet.types[j];
                    if (betsResult[betType] != 1) {
                        continue;
                    }

                    accounts[cnt] = players[i];
                    amounts[cnt] = bet.amounts[j];
                    indexes[cnt] = j;

                    cnt++;
                }
            }
        }
    }
}
