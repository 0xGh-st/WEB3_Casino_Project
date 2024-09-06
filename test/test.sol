// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Baccarat.sol"; // Baccarat.sol의 경로를 맞게 설정해주세요.
import "../src/BaccaratProxy.sol"; // BaccaratProxy.sol의 경로를 맞게 설정해주세요.

contract BaccaratTest is Test {
    Baccarat baccarat;
    BaccaratProxy proxy;
    Baccarat proxyAsBaccarat;
    address owner;
    address player1;
    address player2;
    address player3;
    address player4;
    address player5;

    function setUp() external {
        owner = address(this);
        player1 = address(0x1234);
        player2 = address(0x5678);
        player3 = address(0x9ABC);
        player4 = address(0xDEF0);
        player5 = address(0x1357);

        vm.deal(owner, 100 ether);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(player4, 10 ether);
        vm.deal(player5, 10 ether);

        baccarat = new Baccarat();
        bytes memory data = abi.encodeWithSelector(baccarat.initialize.selector, 0.001 ether, 0.01 ether, 5);
        proxy = new BaccaratProxy(address(baccarat), data);
        proxyAsBaccarat = Baccarat(address(proxy));
    }

	function test_playBaccarat() external {
		vm.startPrank(player1);
		proxyAsBaccarat.placeBet{value: 0.001 ether}(Baccarat.BetType.Player);
		vm.stopPrank();

		vm.startPrank(player2);
		proxyAsBaccarat.placeBet{value: 0.001 ether}(Baccarat.BetType.Banker);
		vm.stopPrank();

		vm.startPrank(player3);
		proxyAsBaccarat.placeBet{value: 0.001 ether}(Baccarat.BetType.Tie);
		vm.stopPrank();

		vm.startPrank(player4);
		proxyAsBaccarat.placeBet{value: 0.001 ether}(Baccarat.BetType.Player);
		vm.stopPrank();

		vm.prank(owner);
		(bool success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSelector(proxyAsBaccarat.resolveBets.selector)
		);
		assertFalse(success, "resolveBets() should fail when Betting Phase");
		(success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSelector(proxyAsBaccarat.claimFee.selector)
		);
		assertFalse(success, "claimFee() should fail when Betting Phase");
		vm.stopPrank();

		vm.startPrank(player5);
		proxyAsBaccarat.placeBet{value: 0.001 ether}(Baccarat.BetType.Banker);
		vm.stopPrank();


		vm.prank(owner);
		(success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSelector(proxyAsBaccarat.resolveBets.selector)
		);
		assertFalse(success, "resolveBets() should fail if called within the same block");

		vm.roll(block.number + 1);
		(success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSelector(proxyAsBaccarat.resolveBets.selector)
		);
		assertFalse(success, "resolveBets() should fail if called within checkPoint + 1");

		vm.roll(block.number + 2);
		proxyAsBaccarat.resolveBets();
		vm.stopPrank();

		address winner0;
		uint256 winnerCount = proxyAsBaccarat.getWinnersCount();
		if (winnerCount > 0) {
			assertEq(uint(proxyAsBaccarat.currentState()), uint(Baccarat.BaccaratStateMachine.ClaimPlayer));

			for (uint256 i = 0; i < winnerCount; i++) {
				address winner = proxyAsBaccarat.winners(i);
				if(i==1){
					winner0 = proxyAsBaccarat.winners(0);
					uint256 reserve = winner0.balance;
					// reclaim
					vm.startPrank(winner0);
					(success, ) = address(proxyAsBaccarat).call(
						abi.encodeWithSelector(proxyAsBaccarat.claimReward.selector)
					);
					assertFalse(success, "Do Not Reclaim");
					vm.stopPrank();

					//state machine
					vm.startPrank(owner);
					(success, ) = address(proxyAsBaccarat).call(
						abi.encodeWithSelector(proxyAsBaccarat.claimFee.selector)
					);
					assertFalse(success, "claimFee() should fail when Resolve Phase");
					vm.stopPrank();

					vm.startPrank(player1);
					(success, ) = address(proxyAsBaccarat).call{value: 0.001 ether}(
						abi.encodeWithSelector(proxyAsBaccarat.placeBet.selector)
					);
					assertFalse(success, "placeBet should fail when Resolve Phase");
					vm.stopPrank();
				}
				vm.startPrank(winner);
				proxyAsBaccarat.claimReward();
				vm.stopPrank();
			}
			assertEq(uint(proxyAsBaccarat.currentState()), uint(Baccarat.BaccaratStateMachine.ClaimOwner));
		} else {
			assertEq(uint(proxyAsBaccarat.currentState()), uint(Baccarat.BaccaratStateMachine.ClaimOwner));
		}

		vm.startPrank(player1);
		(success, ) = address(proxyAsBaccarat).call{value: 0.001 ether}(
			abi.encodeWithSelector(proxyAsBaccarat.placeBet.selector)
		);
		assertFalse(success, "placeBet should fail when Resolve Phase");
		vm.stopPrank();

		vm.startPrank(player1);
		(success, ) = address(proxyAsBaccarat).call{value: 0.001 ether}(
			abi.encodeWithSelector(proxyAsBaccarat.placeBet.selector)
		);
		assertFalse(success, "placeBet should fail when Resolve Phase");
		vm.stopPrank();

		vm.prank(owner);
		proxyAsBaccarat.claimFee();

		assertEq(uint(proxyAsBaccarat.currentState()), uint(Baccarat.BaccaratStateMachine.Bet));
	}

	function test_upgradeImplementation() external {
		Baccarat newBaccarat = new Baccarat();

		// stop 상태여야 upgrade 가능
		vm.prank(owner);
		(bool success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newBaccarat), "")
		);
		assertFalse(success, "Should not allow upgrade when contract is not stopped");

		// Freeze!!!
		proxyAsBaccarat.stopContract();

		// Upgrading... [=======>            ]
		(success, ) = address(proxyAsBaccarat).call(
			abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newBaccarat), "")
		);
		assertTrue(success, "Upgrade should be allowed when contract is stopped");

		//proxyAsBaccarat.initialize(0.002 ether, 0.02 ether, 10);

		vm.startPrank(player4);
		(success, ) = address(proxyAsBaccarat).call{value: 0.001 ether}(
				abi.encodeWithSelector(proxyAsBaccarat.placeBet.selector, Baccarat.BetType.Banker)
		);
		assertFalse(success, "resume please");
		vm.stopPrank();

		vm.startPrank(owner);
		proxyAsBaccarat.resumeContract();
		vm.stopPrank();

		vm.startPrank(player4);
		(success, ) = address(proxyAsBaccarat).call{value: 0.001 ether}(
				abi.encodeWithSelector(proxyAsBaccarat.placeBet.selector, Baccarat.BetType.Banker)
		);
		assertTrue(success, "Baccarat Upgrade Complete");
		vm.stopPrank();
	}


	receive() external payable {}
}

