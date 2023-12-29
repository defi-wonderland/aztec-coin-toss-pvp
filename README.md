# Aztec Coin Toss PvP

Aztec Coin Toss PvP allows any number of users to participate in betting rounds based on a Coin Toss with a 50/50 chance. We leverage the [Aztec Private Oracle](https://github.com/defi-wonderland/aztec-private-oracle/) by choosing a trusted divinity that will provide a random number that determines the outcome of the bet. 

The users that bet and the winners of each round remain fully private at all times. No information is leaked to the outside and only the user knows if they won or lost. This allows users to be able to bet freely on anything they want at all times. 

The Coin Toss PvP works by pairing bets and then distributing the whole raised amount equally amongst the winners. By utilizing the privacy in Aztec, we allow users to create bets on their side and not need to reveal that they won but that _someone_ won. 

You can check our design for the proof of concept on [Figma](https://www.figma.com/file/kNAWjaACCEtOqVn3yrcE9l/Aztec-Coin-Toss-PvP?type=whiteboard&node-id=0%3A1&t=xSSUoPJitueGErHu-1).

![Design](design.png?raw=true)

## Flow:

1. Users bet on the outcome of the toss. Users are limited by time to participate and if they miss it they can enter in the next round of bets.

2. When the time for betting expires, anyone can start the request for the randomness/answer/outcome to the Private Oracle.
    
3. The resolution of the divinity creates a public answer for anyone to see what the result of the round was.

4. The users that won reveal that they won to the Coin Toss contract. (Bear in mind that this works in a fully private way and the only public information is how many users won, not who those users are).

5. After the reveal phase ends, winners can claim their rewards from the contract.

## Installation

1) Install the Aztec Sandbox by following this [guide](https://docs.aztec.network/dev_docs/getting_started/quickstart#install-the-sandbox)

2) To install the Coin Toss, in the root of the project run:
```
yarn
```

## Running tests

With the sandbox running and the project installed, execute this to compile the contracts and run the tests:
```
yarn test
```

## Want to contribute?

If you have ideas on how to make the Coin Toss better, improve its performance or add additional features, don't hesitate to fork and send pull requests!

We also need people to test out pull requests. So take a look through the open issues and help where you want.