# Crowdfunding (MB.io)

## How to run

- Install npm and truffle (`npm install -g truffle`)

- On root folder `npm install && truffle test`.

## Tests

- 1: Deploying an instance of the CrowdFunding
- 2: Create a new Idea
- 3: Create second idea
- 4: Ideas' owner equal to current account
- 5: Idea registered and available
- 6: Register idea, have investor converting Ether into Investor Power. Investor invests more than requested by idea creators. Process is finalized, Ether gets pending to be pulled by idea creators. Investor claims "reward".

During Test #6 the time on the EVM is tweaked.

More unit tests could be included. A big part of the testing was conducted on [Remix IDE](https://remix.ethereum.org) manually.

### Interact with the contract on [Remix IDE](https://remix.ethereum.org)

It is possible to import the dependecies by placing `"github.com/OpenZeppelin"` in the beginning of the import. For example, `import "github.com/OpenZeppelin/openzeppelin-solidity/contracts/math/SafeMath.sol";`. By doing this for all dependencies, compiling and running, the IDE provides a simple UI to interact with the contract.

## Technical and Social pitfalls

#### DoS with (Unexpected) revert

A contract may iterate through an array to pay users (e.g., supporters in a crowdfunding contract). It is important to make sure that each payment succeeds. If not, the system should revert. If one call fails, the whole system reverts, forcing the loop to never finish. This means that no address would get paid, because one address is forcing an error. It is recommended to use a **pull payment** method.

In this contract, it is used the [PullPayment](https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/payment/PullPayment.sol) method by OpenZeppelin (a common standard).

#### [The Ethereum Virtual Machine does not behave well with huge loops](https://stackoverflow.com/questions/48113615/solidity-for-loop-over-a-huge-amount-of-data)

Looping through big loops may not be a good idea when using the Ethereum Virtual Machine. As mentioned before, a **pull payment** mechanism was implemented.

#### Overflows/Underflows

If the integers get too big or too small, they wrap around. This is relevant since users have the ability to increment or decrement their "money" within this contract. For example, when a user votes, his power is decremented. If a safety mechanism was not implemented, he would be able to wrap his voting power around. That would mean something like 2^256 voting power (dangerous!).

For this, it was used OpenZeppelin library, [SafeMath](https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol).

### Design Patterns

- **Mapped Struct with Index**
- **Pausable**: Implementing this allows contract functionality to be stopped.
- **Pull payment**: Implementing this helps protect against re-entrancy and denial of service attacks.
- **Fail early, fail loud**: Functions check requires early in the function body or as modifiers, executed before the main body.
- Not looping through arrays (safety in gas usage).

## Further development

- Timestamps will never be uint256. uint64 would be more than enough.
- Idea struct with Tight Variable Packing. Optimized for gas consumption
- More unit testing...

- As it was not mentioned what to do with the losers' money, it will be trapped in the contract forever. Maybe do something about this in the future.

## Exercise

In this use-case, crowdfunding is set up in two steps. Idea registration, investment and voting, both needs set end times.

### Idea registration

Startups register their ideas with total ether needed, GitHub URL of their white paper,
commit hash.

### Investment and Voting

Investors can send their investments to the contract and then vote for ideas with the
weight of their investment. An investor can vote to multiple ideas and can add more
investment before the investment period ends.

### Final Step

Contract sends the needed amount to the winner idea and returns to remaining amount
to the investors.
