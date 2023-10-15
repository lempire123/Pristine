# Pristine - *CDP for bitcoin*

My inspiration for this protocol was Liquity, a DeFi app I use myself as a way of borrowing money using my Eth as collateral. The reasons I love it so much are twofold:
-  its security (the mechanics of the protocol are "fairly" simple, and it only allows one collateral type - eth)
- Borrowing is interest free! I have a pretty sizable loan which I don't plan to repay for a good few years - the only concern is not getting liquidated - aka don't use too much leverage!

For further reading on Liquidity, read the following docs: https://docs.liquity.org.

No code was copied from liquity. 
Code has not been audited.

# Technical details: 

- Collateral token is wBTC
- Collateral ratio is 110%
- No interest on loans
- Liquidations can happen when collat ratio is < 110%
- On liquidation, the liquidator must repay all the loan, and gets to keep the liquidatee's collateral




