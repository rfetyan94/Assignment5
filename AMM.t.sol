// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol"; 


contract MToken is ERC20 {
	constructor(string memory name, string memory symbol,uint256 supply) ERC20(name,symbol) {
		_mint(msg.sender, supply );
	}
}

contract AMMTest is Test {
    AMM public amm;
	ERC20 public tokenA;
	ERC20 public tokenB;
	uint256 admin_sk = uint256(keccak256(abi.encodePacked("ADMIN")));
	address admin = vm.addr(admin_sk);
	uint256 lp_sk = uint256(keccak256(abi.encodePacked("LP")));
	address lp = vm.addr(lp_sk);

	event Swap( address indexed _inToken, address indexed _outToken, uint256 inAmt, uint256 outAmt );
	event LiquidityProvision( address indexed _from, uint256 AQty, uint256 BQty );
	event Withdrawal( address indexed _from, address indexed recipient, uint256 AQty, uint256 BQty );

    function setUp() public {
		uint256 amtA = 2**50;
		uint256 amtB = 2**50;
		
		vm.startPrank(admin);
		tokenA = new MToken( 'Allosaurus', 'ALRS', 4*amtA);
		tokenB = new MToken( 'Baryonyx', 'BYNX', 4*amtB);
		tokenA.transfer(lp,amtA);
		tokenB.transfer(lp,amtB);
		vm.stopPrank();

		assertEq( tokenA.balanceOf(lp), amtA );
		assertEq( tokenB.balanceOf(lp), amtB );

		vm.startPrank(lp);
		amm = new AMM( address(tokenA), address(tokenB) );
		tokenA.approve( address(amm), amtA );
		tokenB.approve( address(amm), amtB );
		amm.provideLiquidity( amtA, amtB );
		vm.stopPrank();

		assertEq( tokenA.balanceOf(address(amm)), amtA );
		assertEq( tokenB.balanceOf(address(amm)), amtB );
    }

    function testSwap(address userA, address userB, uint256 ratioA, uint256 ratioB ) public {
		vm.assume( ratioA > 4*10**6 );
		vm.assume( ratioB > 4*10**6 );
		vm.assume( userA != address(0) );
		vm.assume( userB != address(0) );
		vm.assume( userA != userB );

		uint256 amtA = Math.min(tokenA.balanceOf(address(amm))*(ratioA % 2**100)/10**9,tokenA.balanceOf(admin));
		uint256 amtB = Math.min(tokenB.balanceOf(address(amm))*(ratioB % 2**100)/10**9,tokenB.balanceOf(admin));
		
		vm.startPrank(admin);
		tokenA.transfer( userA, amtA );
		tokenB.transfer( userB, amtB );
		vm.stopPrank();

		uint256 prevBalA = tokenA.balanceOf(userA);
		uint256 prevBalB = tokenB.balanceOf(userA);

		vm.expectEmit(true, true, false, false );
		vm.startPrank(userA);
		emit Swap( address(tokenA), address(tokenB), amtA, 0 );
		tokenA.approve(address(amm),amtA);
		amm.tradeTokens( address(tokenA), amtA );
		vm.stopPrank();

		uint256 balInBefore = tokenA.balanceOf(address(amm));
		uint256 balOutBefore = tokenB.balanceOf(address(amm));
		uint256 amountInWithFee = amtA * 9997 / 10000;
		uint256 expectedOut = balOutBefore - (balInBefore * balOutBefore) / (balInBefore + amountInWithFee);
		//Change this to actually calculate amount
		assertEq(tokenB.balanceOf(userA), prevBalB + expectedOut);

		prevBalA = tokenA.balanceOf(userB);
		prevBalB = tokenB.balanceOf(userB);
		vm.expectEmit(true, true, false, false );
		vm.startPrank(userB);
		tokenB.approve(address(amm),amtB);
		emit Swap( address(tokenB), address(tokenA), amtB, 0 );
		amm.tradeTokens( address(tokenB), amtB );
		vm.stopPrank();

		balInBefore = tokenB.balanceOf(address(amm));
		balOutBefore = tokenA.balanceOf(address(amm));
		amountInWithFee = amtB * 9997 / 10000;
		expectedOut = balOutBefore - (balInBefore * balOutBefore) / (balInBefore + amountInWithFee);
		//Change this to actually calculate amount
		assertEq(tokenA.balanceOf(userB), prevBalA + expectedOut);
    }

    function testWithdrawalA( address recipient, uint256 amtA ) public {
		vm.assume( amtA > 0 );
		vm.assume( recipient != address(0) );
		uint256 amt = Math.min(tokenA.balanceOf(address(amm)),amtA); 
		uint256 prevBalRecipient = tokenA.balanceOf(recipient);
		uint256 prevBalAMM = tokenA.balanceOf(address(amm));
		vm.expectEmit(true, true, false, true );
		emit Withdrawal( lp, recipient, amt, 0 );
		vm.prank(lp);
		amm.withdrawLiquidity(recipient,amt,0);
		assertEq( tokenA.balanceOf(recipient), prevBalRecipient + amt );
		assertEq( tokenA.balanceOf(address(amm)), prevBalAMM -  amt );
    }

    function testUnauthorizedWithdrawalA( address withdrawer, address recipient, uint256 amtA ) public {
		vm.assume( amtA > 0 );
		vm.assume(withdrawer != lp );
		vm.assume( recipient != address(0) );
		uint256 amt = Math.min(tokenA.balanceOf(address(amm)),amtA); 
		vm.expectRevert();
		vm.prank(withdrawer);
		amm.withdrawLiquidity(recipient,amt,0);
    }

    function testUnauthorizedDepositWithdrawalA( address withdrawer, address recipient, uint256 _amtA, uint256 _amtB) public {
		vm.assume( _amtA > 0 );
		vm.assume( _amtB > 0 );
		vm.assume(withdrawer != lp );
		vm.assume(withdrawer != address(0));
		vm.assume( recipient != address(0) );
		vm.assume( recipient != withdrawer );
		uint256 amtA = Math.min(tokenA.balanceOf(admin),_amtA); 
		uint256 amtB = Math.min(tokenB.balanceOf(admin),_amtB); 
		vm.startPrank(admin);
		tokenA.transfer(withdrawer,amtA);
		tokenB.transfer(withdrawer,amtB);
		vm.stopPrank();
		vm.startPrank(withdrawer);
		tokenA.approve(address(amm),amtA);
		tokenB.approve(address(amm),amtB);
		amm.provideLiquidity( amtA, amtB );
		vm.expectRevert();
		amm.withdrawLiquidity(recipient,amtA,0);
		vm.stopPrank();
    }

}
