var CrowdFunding = artifacts.require("./CrowdFunding.sol");

const now = new Date().getTime() / 1000;
const registrationPeriodEnd = now + 86400;
const investingPeriodEnd = registrationPeriodEnd + 86400 * 5;

module.exports = function(deployer) {
  deployer.deploy(CrowdFunding, registrationPeriodEnd, investingPeriodEnd);
};
