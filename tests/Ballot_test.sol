// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
import "hardhat/console.sol";
import "../contracts/3_Ballot.sol";

contract BallotTest {

    bytes32[] proposalNames;

    Ballot ballotToTest;
    function beforeAll () public {
        proposalNames.push(bytes32("candidate1"));
        ballotToTest = new Ballot(proposalNames);
    }

    function checkWinningProposal () public {
        console.log("Running checkWinningProposal");
        ballotToTest.vote(0);
        Assert.equal(ballotToTest.winningProposal(), uint(0), "proposal at index 0 should be the winning proposal");
        Assert.equal(ballotToTest.winnerName(), bytes32("candidate1"), "candidate1 should be the winner name");
    }

    function checkWinninProposalWithReturnValue () public view returns (bool) {
        return ballotToTest.winningProposal() == 0;
    }

    // 返回合约ETH余额
    function getBalance() public view returns (uint256) {
        uint256 balance = address(this).balance;
        console.log("Contract balance:", balance);
        return balance;
    }

    function getAddress() public view returns (address) {
        console.log(address(this));
        return address(this);
    }
    // 返回调用者的ETH余额
    function getCallerBalance() public view returns (uint256) {
        address caller = msg.sender;
        uint256 balance = caller.balance;
        console.log("Caller address:", caller);
        console.log("Caller balance:", balance);
        return balance;
    }
}