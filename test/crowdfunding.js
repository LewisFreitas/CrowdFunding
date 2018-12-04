var CrowdFunding = artifacts.require("./CrowdFunding.sol");

function increaseTime(addSeconds) {
  web3.currentProvider.sendAsync(
    {
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      params: [addSeconds],
      id: new Date().getSeconds()
    },
    err => {
      if (!err) {
        web3.currentProvider.send({
          jsonrpc: "2.0",
          method: "evm_mine",
          params: [],
          id: new Date().getSeconds()
        });
      }
    }
  );
}

contract("Campaign", async accounts => {
  let crowdFundingInstance;

  let registrationPeriodStart;
  let registrationPeriodEnd;
  let investingPeriodStart;
  let investingPeriodEnd;

  beforeEach("setup for each test", async () => {
    crowdFundingInstance = await CrowdFunding.deployed();
  });

  // Test to see whether CrowdFunding deploys.
  it("...should deploy CrowdFunding instance.", async () => {
    const dates = await crowdFundingInstance.getDates.call();

    registrationPeriodStart = dates[0];
    registrationPeriodEnd = dates[1];
    investingPeriodStart = dates[2];
    investingPeriodEnd = dates[3];

    assert.ok(crowdFundingInstance, "Did not deploy CrowdFunding.");
  });

  it("...should create a new idea", async () => {
    await crowdFundingInstance.createIdea(
      "github.com/LewisFreitas/proofile",
      "41fccbe0b9459ee58d67fda2faae094b53cc0418",
      100000,
      {
        from: accounts[0]
      }
    );
    let numberRegisteredIdeas = await crowdFundingInstance.getTotalIdeasRegistered.call();
    assert.equal(numberRegisteredIdeas, 1, "Did not create idea successfully!");
  });

  it("...should create a second new idea", async () => {
    await crowdFundingInstance.createIdea(
      "github.com/LewisFreitas/idea-2",
      "5a3ccce1b9459ee58d67fda2faae094b53cc0418",
      300000,
      {
        from: accounts[0]
      }
    );
    let numberRegisteredIdeas = await crowdFundingInstance.getTotalIdeasRegistered.call();
    assert.equal(numberRegisteredIdeas, 2, "Did not create idea successfully!");
  });

  it("...should have idea's owner address equal to current account.", async () => {
    const idea = await crowdFundingInstance.getIdeaByIndex.call(0);

    assert.equal(
      idea[4], // idea.owner
      accounts[0],
      "Idea should have manager address equal to current account."
    );
  });

  it("...should have idea's registered and available.", async () => {
    const idea = await crowdFundingInstance.getIdeaByIndex.call(0);

    assert.equal(
      idea[3],
      true,
      "Idea should have registered value equal to true."
    );

    assert.equal(
      idea[7],
      true,
      "Idea should have available value equal to true."
    );
  });

  it("...should register an idea, have an investor(s) investing on it, finalize the process and claim the money raised and the excess by the investor(s).", async () => {
    const _githubURL = "github.com/test/test";
    const _commitHash = "41fccbe0b9459ee58d67fda2faae094b53cc0418";
    const _amountNeeded = 10000;

    // Checking if already in investing period.
    const isRegisterPeriod = await crowdFundingInstance.isRegistrationPeriod.call();
    assert.equal(isRegisterPeriod, true, "Should be in register period.");

    const txResult1 = await crowdFundingInstance
      .createIdea(_githubURL, _commitHash, _amountNeeded, {
        from: accounts[0]
      })
      .then(result => result);

    // CreateIdea event emitted during idea creation
    const event1 = {
      name: txResult1.logs[0].event,
      index: txResult1.logs[0].args.index
    };

    assert.equal(event1.name, "CreateIdea", "Event name should be CreateIdea.");

    // INVESTING PERIOD STARTS
    // LET'S HACK THE EVM

    increaseTime(90000);

    // Checking if already in investing period.
    const isInvestingPeriod = await crowdFundingInstance.isInvestingPeriod.call();
    assert.equal(isInvestingPeriod, true, "Should be in investing period.");

    const _investment = 100000;
    /*2 - Investor sends money to contract*/
    const txResult2 = await crowdFundingInstance
      .sendInvestment({
        value: _investment,
        from: accounts[1]
      })
      .then(result => result);

    // SendInvestment event emitted
    const event2 = {
      name: txResult2.logs[0].event,
      investor: txResult2.logs[0].args.investor,
      amount: txResult2.logs[0].args.amount
    };

    assert.equal(
      event2.name,
      "SentInvestment",
      "Event name should be SentInvestment."
    );

    const investorPower = await crowdFundingInstance.getInvestorPowerByAddress.call(
      accounts[1]
    );

    assert.equal(
      investorPower,
      _investment,
      "Investor power should be equals to " + _investment
    );

    await crowdFundingInstance.vote(event1.index, _investment, {
      from: accounts[1]
    });

    const idea = await crowdFundingInstance.getIdeaByIndex.call(event1.index);

    assert.equal(
      idea[5],
      _investment,
      "Number of votes should be equal to " + _investment
    );

    assert.equal(idea[6], 1, "Number of contributors should be equal to " + 1);

    // INVESTING PERIOD HAS ENDED
    // LET'S HACK THE EVM

    increaseTime(90000 * 5);

    await crowdFundingInstance.finalize({ from: accounts[0] });

    const winnerPayment = await crowdFundingInstance.payments.call(accounts[0]);

    assert.equal(
      _amountNeeded,
      winnerPayment,
      "Amount needed should be equal to " + idea[2]
    );

    const txResult3 = await crowdFundingInstance
      .claimReward({ from: accounts[1] })
      .then(result => result);

    const investorReward = await crowdFundingInstance.payments.call(
      accounts[1]
    );

    assert.equal(
      investorReward,
      90000,
      "Amount needed should be equal to 9000."
    );
  });
});
