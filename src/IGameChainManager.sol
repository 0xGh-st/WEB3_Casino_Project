// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGameChainManager {

    function updateIncome(uint256 _tableId, uint256 _roundId, int256 _income) external;
    function refillETH(address _account) external;
    function transferToken(address _account, uint256 _amount) external;
}
