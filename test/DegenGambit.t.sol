// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {DegenGambit} from "../src/DegenGambit.sol";

contract TestableDegenGambit is DegenGambit {
    mapping(address => uint256) public EntropyForPlayer;

    constructor(
        uint256 blocksToAct,
        uint256 costToSpin,
        uint256 costToRespin
    ) DegenGambit(blocksToAct, costToSpin, costToRespin) {}

    function setEntropy(address player, uint256 entropy) public {
        EntropyForPlayer[player] = entropy;
    }

    function _entropy(address player) internal view override returns (uint256) {
        return EntropyForPlayer[player];
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract DegenGambitTest is Test {
    TestableDegenGambit public degenGambit;

    uint256 blocksToAct = 20;
    uint256 costToSpin = 0.1 ether;
    uint256 costToRespin = 0.07 ether;

    uint256 player1PrivateKey = 0x13371;
    address player1 = vm.addr(player1PrivateKey);

    // Events for testing
    event Spin(address indexed player, bool indexed bonus);
    event Award(address indexed player, uint256 value);

    function setUp() public {
        degenGambit = new TestableDegenGambit(
            blocksToAct,
            costToSpin,
            costToRespin
        );

        vm.deal(address(degenGambit), costToSpin << 30);
        vm.deal(player1, 10 * costToSpin);
    }

    function test_spinCost_discount_in_and_only_in_first_blocksToAct_blocks_on_chain()
        public
    {
        uint256 i;
        for (i = 1; i <= blocksToAct; i++) {
            assertEq(block.number, i);
            assertEq(degenGambit.spinCost(player1), degenGambit.CostToRespin());
            vm.roll(block.number + 1);
        }

        assertEq(block.number, degenGambit.BlocksToAct() + 1);
        assertEq(degenGambit.spinCost(player1), degenGambit.CostToSpin());
    }

    function test_spin_fails_with_insufficient_value() public {
        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        uint256 cost = degenGambit.spinCost(player1);

        vm.startPrank(player1);

        vm.expectRevert(DegenGambit.InsufficientValue.selector);
        degenGambit.spin{value: cost - 1}(false);

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(gameBalanceFinal, gameBalanceInitial);
        assertEq(playerBalanceFinal, playerBalanceInitial);
    }

    function test_spin_takes_all_sent_value() public {
        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        uint256 cost = degenGambit.spinCost(player1);

        vm.startPrank(player1);

        degenGambit.spin{value: 2 * cost}(false);

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(gameBalanceFinal, gameBalanceInitial + 2 * cost);
        assertEq(playerBalanceFinal, playerBalanceInitial - 2 * cost);
    }

    function test_respin_succeeds_immediately() public {
        vm.roll(block.number + blocksToAct + 1);

        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        vm.startPrank(player1);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToSpin}(false);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToRespin}(false);

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(
            gameBalanceFinal,
            gameBalanceInitial + costToSpin + costToRespin
        );
        assertEq(
            playerBalanceFinal,
            playerBalanceInitial - costToSpin - costToRespin
        );
    }

    function test_respin_succeeds_at_deadline() public {
        vm.roll(block.number + blocksToAct + 1);

        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        vm.startPrank(player1);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToSpin}(false);

        vm.roll(block.number + blocksToAct);
        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToRespin}(false);

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(
            gameBalanceFinal,
            gameBalanceInitial + costToSpin + costToRespin
        );
        assertEq(
            playerBalanceFinal,
            playerBalanceInitial - costToSpin - costToRespin
        );
    }

    function test_respin_fails_after_deadline() public {
        vm.roll(block.number + blocksToAct + 1);

        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        vm.startPrank(player1);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToSpin}(false);

        vm.roll(block.number + blocksToAct + 1);
        vm.expectRevert(DegenGambit.InsufficientValue.selector);
        degenGambit.spin{value: costToRespin}(false);

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(gameBalanceFinal, gameBalanceInitial + costToSpin);
        assertEq(playerBalanceFinal, playerBalanceInitial - costToSpin);
    }

    // Entropy was constructed using the generate_outcome_tests() method in the Degen Gambit game design notebook.
    function test_spin_2_2_2_0_false_large_pot() public {
        vm.roll(block.number + blocksToAct + 1);

        // Guarantees that the payout does not fall under balance-based clamping flow.
        vm.deal(address(degenGambit), costToSpin << 30);

        uint256 entropy = 143946520351854296877309383;

        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        vm.startPrank(player1);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToSpin}(false);
        degenGambit.setEntropy(player1, entropy);

        uint256 gameBalanceIntermediate = address(degenGambit).balance;
        uint256 playerBalanceIntermediate = player1.balance;

        assertEq(gameBalanceIntermediate, gameBalanceInitial + costToSpin);
        assertEq(playerBalanceIntermediate, playerBalanceInitial - costToSpin);

        uint256 expectedPayout = degenGambit.payout(2, 2, 2);
        assertEq(expectedPayout, 50 * costToSpin);

        vm.roll(block.number + 1);

        vm.expectEmit();
        emit Award(player1, expectedPayout);
        (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy
        ) = degenGambit.accept();

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(left, 2);
        assertEq(center, 2);
        assertEq(right, 2);
        assertEq(remainingEntropy, 0);
        assertEq(gameBalanceFinal, gameBalanceIntermediate - expectedPayout);
        assertEq(
            playerBalanceFinal,
            playerBalanceIntermediate + expectedPayout
        );
    }

    // Entropy was constructed using the generate_outcome_tests() method in the Degen Gambit game design notebook.
    function test_spin_2_2_2_0_false_small_pot() public {
        vm.roll(block.number + blocksToAct + 1);

        // Guarantees that the payout falls under balance-based clamping flow.
        vm.deal(address(degenGambit), costToSpin);

        uint256 entropy = 143946520351854296877309383;

        uint256 gameBalanceInitial = address(degenGambit).balance;
        uint256 playerBalanceInitial = player1.balance;

        vm.startPrank(player1);

        vm.expectEmit();
        emit Spin(player1, false);
        degenGambit.spin{value: costToSpin}(false);
        degenGambit.setEntropy(player1, entropy);

        uint256 gameBalanceIntermediate = address(degenGambit).balance;
        uint256 playerBalanceIntermediate = player1.balance;

        assertEq(gameBalanceIntermediate, gameBalanceInitial + costToSpin);
        assertEq(playerBalanceIntermediate, playerBalanceInitial - costToSpin);

        uint256 expectedPayout = degenGambit.payout(2, 2, 2);
        assertEq(expectedPayout, address(degenGambit).balance >> 6);

        vm.roll(block.number + 1);

        vm.expectEmit();
        emit Award(player1, expectedPayout);
        (
            uint256 left,
            uint256 center,
            uint256 right,
            uint256 remainingEntropy
        ) = degenGambit.accept();

        vm.stopPrank();

        uint256 gameBalanceFinal = address(degenGambit).balance;
        uint256 playerBalanceFinal = player1.balance;

        assertEq(left, 2);
        assertEq(center, 2);
        assertEq(right, 2);
        assertEq(remainingEntropy, 0);
        assertEq(gameBalanceFinal, gameBalanceIntermediate - expectedPayout);
        assertEq(
            playerBalanceFinal,
            playerBalanceIntermediate + expectedPayout
        );
    }
}