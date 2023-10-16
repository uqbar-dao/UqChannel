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
        UqChannel.Participant memory aliPart = UqChannel.Participant(ali, aliChannelPubKey, 1000);
        UqChannel.Participant memory bobPart = UqChannel.Participant(bob, bobChannelPubKey, 1000);

        uint256 correctId = uint256(keccak256(abi.encodePacked(ali, bob, aliChannelPubKey, bobChannelPubKey)));

        vm.expectEmit(true, true, false, true);
        emit Transfer(ali, address(uqChannel), 1000);
        vm.expectEmit(true, true, false, true);
        emit Transfer(bob, address(uqChannel), 1000);
        vm.expectEmit(true, true, true, true);
        emit ChannelCreated(correctId, ali, bob, aliChannelPubKey, bobChannelPubKey, 1000, 1000, address(token));
        uint256 actualId = uqChannel.makeChannel(aliPart, bobPart, IERC20(token));
        assertEq(actualId, correctId);
    }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
