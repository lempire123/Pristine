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
- **Redemption process** Detailed description below.

## **Redemption Process**

Pristine proposes an innovative redemption process that dynamically adjusts the redemption rate based on the collateral ratio of a position. This mechanism is designed to incentivize redemptions against riskier positions, thus enhancing the overall stability of the system. Unlike Liquity, which maintains a static redemption rate, Pristine's dynamic rate adjustment aligns the incentives of all participants and adds a layer of security and efficiency to the ecosystem.

Here’s a breakdown of the Pristine Redemption Process:

### **Dynamic Redemption Rate:**
In Pristine, the redemption rate is a function of the collateral ratio. The objective is to incentivize individuals to redeem against positions that are riskier, hereby defined as having lower collateral ratios. The redemption rates are structured as follows:

- **Collateral Ratio 110% - 140%:** Redemption rate is $1.00 per Satoshi Stablecoin.
- **Collateral Ratio 140% - 180%:** Redemption rate is $0.97 per Satoshi Stablecoin.
- **Collateral Ratio above 180%:** Redemption rate is $0.95 per Satoshi Stablecoin.

This dynamic redemption rate mechanism is beneficial in multiple ways:

- **Risk Mitigation:** By incentivizing redemptions against riskier positions, Pristine helps in reducing the systemic risk and ensuring a healthier collateralization ratio across the ecosystem.
  
- **Enhanced Stability:** The dynamic redemption rate acts as a stabilizing mechanism, providing a buffer against market volatility and ensuring that redemptions are more aligned with the overall health of the system.
  
- **Incentive Alignment:** The varying redemption rates create a natural incentive for participants to act in a manner that promotes system stability.

### **Comparative Advantage Over Liquity:**
Unlike Liquity's one-size-fits-all redemption rate of $1.00, Pristine’s dynamic redemption rate provides a more nuanced approach to manage redemptions in alignment with the system's health. This not only promotes better risk management but also fosters a more resilient and user-centric borrowing experience in the Pristine ecosystem. 

Explore the technical intricacies of this innovative redemption process in the [smart contract code](./src/Pristine.sol) or delve into the [testing suite](./test) to see it in action.

## **Project Setup**

### **Prerequisites**

Before diving into the code, ensure you have foundry installed:

- **[Foundry](https://book.getfoundry.sh/getting-started/installation)** 

### **Cloning the Project**

To work on this project locally, you'll need to clone the repository to your machine:

```sh
git clone https://github.com/lempire123/Pristine.git Pristine
cd Pristine
```

- **Smart Contracts:** Located [here](./src). Build with the command:
  ```sh
  forge build 
  ```

- **Tests:** Available [here](./test). Run using the command:
  ```sh
  forge test -vvv
    ```

