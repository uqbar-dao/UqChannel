// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { UqChannel } from "../src/UqChannel.sol";
import { TestERC20 } from "../src/test/TestERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CounterTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event ChannelCreated(
        uint256 indexed id,
        address indexed ali,
        address indexed bob,
        address aliChannelKey,
        address bobChannelKey,
        uint256 aliBalance,
        uint256 bobBalance,
        address token
    );

    event ChannelUpdated(
        uint256 indexed id,
        uint256 messageId,
        bytes32 stateHash,
        uint256 aliBalance,
        uint256 bobBalance,
        uint256 challengePeriod
    );

    // other info should be indexed already, no reason to re-emit
    event ChannelClosed(
        uint256 indexed id,
        uint256 messageId,
        bytes32 stateHash,
        uint256 aliBalance,
        uint256 bobBalance
    );

    struct Participant {
        address participant;
        address channelKey;
        uint256 balance;
    }

    UqChannel public uqChannel;
    TestERC20 public token;
    address public ali = address(0xcafebabe);
    address public bob = address(0xdeadbeef);
    address public aliChannelPubKey;
    address public bobChannelPubKey;
    uint256 public aliChannelSecretKey;
    uint256 public bobChannelSecretKey;

    function setUp() public {
        uqChannel = new UqChannel();
        token = new TestERC20();

        (aliChannelPubKey, aliChannelSecretKey) = makeAddrAndKey("alice");
        (bobChannelPubKey, bobChannelSecretKey) = makeAddrAndKey("bob");

        token.mint(ali, 1000);
        token.mint(bob, 1000);

        vm.prank(ali);
        token.approve(address(uqChannel), 1000);
        assertEq(token.allowance(ali, address(uqChannel)), 1000);

        vm.prank(bob);
        token.approve(address(uqChannel), 1000);
        assertEq(token.allowance(bob, address(uqChannel)), 1000);
    }

    function test_makeChannel() public {
        uint256 correctId = uint256(keccak256(abi.encodePacked(ali, bob, aliChannelPubKey, bobChannelPubKey)));

        vm.expectEmit(true, true, false, true);
        emit Transfer(ali, address(uqChannel), 1000);
        vm.expectEmit(true, true, false, true);
        emit Transfer(bob, address(uqChannel), 1000);
        vm.expectEmit(true, true, true, true);
        emit ChannelCreated(correctId, ali, bob, aliChannelPubKey, bobChannelPubKey, 1000, 1000, address(token));
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));
        assertEq(actualId, correctId);
    }

    function test_updateChannelRevertsIfChannelBalancesDontAddUp() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(100),
            uint256(100),
            bytes32("foo")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest);
        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);

        vm.expectRevert("UqChannel: balances must add up");
        uqChannel.updateChannel(actualId, 1, 100, 100, bytes32("foo"), aliSig, bobSig);
    }

    function test_updateChannelFailsIfStateNotAdvanced() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest = keccak256(abi.encodePacked(
            actualId,
            uint256(0),
            uint256(900),
            uint256(1100),
            bytes32("foo")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest);
        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);

        vm.expectRevert("UqChannel: must advance the state");
        uqChannel.updateChannel(actualId, 0, 900, 1100, bytes32("foo"), aliSig, bobSig);
    }

    function test_updateChannelRevertsIfSigsWrong() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(900),
            uint256(1100),
            bytes32("foo")
        ));

        bytes32 wrongDigest = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(900),
            uint256(1100),
            bytes32("bar")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest);
        (uint8 vaw, bytes32 raw, bytes32 saw) = vm.sign(aliChannelSecretKey, wrongDigest);
        (uint8 vbw, bytes32 rbw, bytes32 sbw) = vm.sign(bobChannelSecretKey, wrongDigest);

        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);
        bytes memory aliSigWrong = abi.encodePacked(raw, saw, vaw);
        bytes memory bobSigWrong = abi.encodePacked(rbw, sbw, vbw);

        vm.expectRevert("UqChannel: invalid ali signature");
        uqChannel.updateChannel(actualId, 1, 900, 1100, bytes32("foo"), aliSigWrong, bobSig);

        vm.expectRevert("UqChannel: invalid bob signature");
        uqChannel.updateChannel(actualId, 1, 900, 1100, bytes32("foo"), aliSig, bobSigWrong);
    }

    function test_updateChannel() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest1 = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(900),
            uint256(1100),
            bytes32("foo")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest1);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest1);
        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);

        vm.expectEmit(true, false, false, true);
        emit ChannelUpdated(actualId, 1, bytes32("foo"), 900, 1100, block.timestamp + 5 minutes);
        uqChannel.updateChannel(actualId, 1, 900, 1100, bytes32("foo"), aliSig, bobSig);
    
        (
            address cAli,
            address cAliChannelkey,
            uint256 cAliBalance,
            address cBob,
            address cBobChannelKey,
            uint256 cBobBalance,
            IERC20 cToken,
            uint256 cMessageId,
            bytes32 cStateHash,
            uint256 cChallengePeriod
        ) = uqChannel.channels(actualId);
    
        assertEq(cAliBalance, 900);
        assertEq(cBobBalance, 1100);
        assertEq(cMessageId, 1);
        assertEq(cStateHash, bytes32("foo"));
        assertEq(cChallengePeriod, block.timestamp + 5 minutes);

        bytes32 digest2 = keccak256(abi.encodePacked(
            actualId,
            uint256(2),
            uint256(800),
            uint256(1200),
            bytes32("bar")
        ));

        (uint8 va2, bytes32 ra2, bytes32 sa2) = vm.sign(aliChannelSecretKey, digest2);
        (uint8 vb2, bytes32 rb2, bytes32 sb2) = vm.sign(bobChannelSecretKey, digest2);
        bytes memory aliSig2 = abi.encodePacked(ra2, sa2, va2);
        bytes memory bobSig2 = abi.encodePacked(rb2, sb2, vb2);

        vm.expectEmit(true, false, false, true);
        emit ChannelUpdated(actualId, 2, bytes32("bar"), 800, 1200, block.timestamp + 5 minutes);
        uqChannel.updateChannel(actualId, 2, 800, 1200, bytes32("bar"), aliSig2, bobSig2);
    
        (
            address cAli2,
            address cAliChannelkey2,
            uint256 cAliBalance2,
            address cBob2,
            address cBobChannelKey2,
            uint256 cBobBalance2,
            IERC20 cToken2,
            uint256 cMessageId2,
            bytes32 cStateHash2,
            uint256 cChallengePeriod2
        ) = uqChannel.channels(actualId);
    
        assertEq(cAliBalance2, 800);
        assertEq(cBobBalance2, 1200);
        assertEq(cMessageId2, 2);
        assertEq(cStateHash2, bytes32("bar"));
        assertEq(cChallengePeriod2, block.timestamp + 5 minutes);
    }

    function test_withdrawTokensFailsIfChallengePeriodNotOver() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(900),
            uint256(1100),
            bytes32("foo")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest);
        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);

        uqChannel.updateChannel(actualId, 1, 900, 1100, bytes32("foo"), aliSig, bobSig);

        vm.expectRevert("UqChannel: challenge period not over yet");
        uqChannel.withdrawTokens(actualId);
    }

    function test_withdrawTokens() public {
        uint256 actualId = uqChannel.makeChannel(ali, aliChannelPubKey, 1000, bob, bobChannelPubKey, 1000, IERC20(token));

        bytes32 digest = keccak256(abi.encodePacked(
            actualId,
            uint256(1),
            uint256(900),
            uint256(1100),
            bytes32("foo")
        ));

        (uint8 va, bytes32 ra, bytes32 sa) = vm.sign(aliChannelSecretKey, digest);
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(bobChannelSecretKey, digest);
        bytes memory aliSig = abi.encodePacked(ra, sa, va);
        bytes memory bobSig = abi.encodePacked(rb, sb, vb);

        uqChannel.updateChannel(actualId, 1, 900, 1100, bytes32("foo"), aliSig, bobSig);

        vm.warp(block.timestamp + 5 minutes + 1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(uqChannel), ali, 900);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(uqChannel), bob, 1100);
        vm.expectEmit(true, false, false, true);
        emit ChannelClosed(actualId, 1, bytes32("foo"), 900, 1100);
        uqChannel.withdrawTokens(actualId);

        assertEq(token.balanceOf(ali), 900);
        assertEq(token.balanceOf(bob), 1100);
    }
}
