# **Pristine**: Stablecoin Backed by Bitcoin

Inspired by Liquity, a decentralized finance (DeFi) application I frequently use to borrow funds against my Ethereum holdings, Pristine aims to bring a robust and user-friendly borrowing experience to the Bitcoin ecosystem.

I admire Liquity for its:
- **Security:** The protocol is fairly straightforward, focusing solely on Ethereum as collateral.
- **Interest-free Borrowing:** With a significant loan that I don’t intend to repay soon, the only concern is avoiding liquidation by maintaining a safe leverage.

Explore more about Liquity in their [documentation](https://docs.liquity.org).

## **Goals**

Pristine strives to create a stablecoin anchored by the unparalleled liquidity and reputation of Bitcoin. While there are existing protocols enabling stablecoin minting backed by Bitcoin, Pristine sets itself apart by exclusively accepting Bitcoin as collateral and offering an interest-free borrowing experience.

## **Technical Details**

- **Collateral Token:** Wrapped Bitcoin (wBTC), renowned as the hardest asset.
- **Collateral Ratio:** 110%.
- **Interest on Loans:** None.
- **Liquidation Threshold:** Triggered when the collateral ratio falls below 110%.
- **Liquidation Process:** Liquidators are required to repay the entire loan to claim the collateral.

## **Code Structure**

## **Prerequisites**

Before diving into the code, ensure you have the following prerequisites installed and set up:

- **[Foundry](https://foundry.link/):** Make sure to install and configure Foundry as it is essential for building and testing the smart contracts in this project.

## **Cloning the Project**

To work on this project locally, you'll need to clone the repository to your machine:

```sh
git clone https://github.com/<Original-Repo-Username>/<Repo-Name>.git
cd <Repo-Name>
```

- **Smart Contracts:** Located [here](./src). Build with the command:
  ```sh
  forge build 
  ```

- **Tests:** Available [here](./test). Run using the command:
  ```sh
  forge test -vvv
    ```

