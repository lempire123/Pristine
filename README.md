# Pristine - *CDP for bitcoin*

My inspiration for this protocol was Liquity, a DeFi app I use myself as a way of borrowing money using my Eth as collateral. The reason I love it so much is its security (the mechanics of the protocol are "fairly" simple, and it only allows one collateral type - eth), and, importantly, borrowing is interest free! 

The following is protocol similar to https://docs.liquity.org. So read those docs for more detail on how CDPs work.

No code was copied from liquity. 
Code has not been audited.

# Technical details: 

- Collateral token is wBTC
- Collateral ratio is 110%
- No interest on loans
- Liquidations can happen when collat ratio is < 110%
- On liquidation, the liquidator must repay all the loan, and gets to keep the liquidatee's collateral




