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

- **Smart Contracts:** Located [here](./src). Build with the command:
  ```sh
  forge build 
  ```

- **Test:** Available [here](./test). Run using the command:
 ```sh
  forge test -vvv
```

