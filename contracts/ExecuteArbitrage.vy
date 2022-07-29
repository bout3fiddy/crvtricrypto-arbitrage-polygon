"""
@title Simple Arbitrage Contract
@author Curve.fi
"""
from vyper.interfaces import ERC20


interface SushiPool:
    def getReserves() -> (uint256, uint256, uint256): view
    def swap(
        amount_0_Out: uint256, 
        amount_1_out: uint256, 
        to: address, 
        data: Bytes[64]
    ): nonpayable

interface CurveCryptoSwap:
    def get_dy(_pool: address, i: uint256, j: uint256, _dx: uint256) -> uint256: view
    def exchange(
        _pool: address, 
        i: uint256, 
        j: uint256, 
        _dx: uint256, 
        _min_dy: uint256, 
        _use_eth: bool, 
        _receiver: address
    ) -> uint256: nonpayable


CRV: constant(address) = 0x172370d5Cd63279eFa6d502DAB29171933a610AF
WETH: constant(address) = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
ZAP: constant(address) = 0x3d8EADb739D1Ef95dd53D718e4810721837c69c1
SUSHI_POOL: constant(address) = 0x396E655C309676cAF0acf4607a868e0CDed876dB
CRVTRICRPTO_POOL: constant(address) = 0xa94fE71A7aAEbBcaEb3f43F839bBc3C5A2D287AD

owner: address
sushi_pool: address
curve_metatricrypto_zap: address


@external
def __init__(
    _owner: address, 
):
    self.owner = msg.sender


# Sushiswap related internal helper functions


@pure
@internal
def get_amount_out(
    amount_in: uint256, reserve_in: uint256, reserve_out: uint256
) -> uint256:
    """
    @dev Given an input amount of an asset and pair reserves, returns the maximum output
        amount of the other asset.
    """
    assert amount_in > 0
    assert reserve_in > 0 and reserve_out > 0
    amount_in_with_fee: uint256 = amount_in * 997
    numerator: uint256 = amount_in_with_fee * reserve_out
    denominator: uint256 = reserve_in * 1000 + amount_in_with_fee
    return numerator / denominator


# Our arbitrage functions


@external
def arbitrage_curve(weth_in: uint256):
    """
    @notice Buy crv (low) on curve and sell (high) on sushi
    @dev callable by anyone
    param amount_weth: Amount of WETH to sell on curve for crv
    """
    reserve_0: uint256 = 0
    reserve_1: uint256 = 0
    timestamp_last: uint256 = 0

    # ---- check we will we receive more than we input ----

    crv_received: uint256 = CurveCryptoSwap(ZAP).get_dy(CRVTRICRPTO_POOL, 5, 0, weth_in)

    reserve_0, reserve_1, timestamp_last = SushiPool(SUSHI_POOL).getReserves()
    weth_received: uint256 = self.get_amount_out(crv_received, reserve_0, reserve_1)

    # if we will receive less than we put in, we cannot arbitrage:
    assert weth_received > weth_in
    
    # ---- execute the arbitrage ----

    # perform curve swap and send to sushi pool
    ERC20(WETH).transferFrom(msg.sender, self, weth_in)
    ERC20(WETH).approve(ZAP, weth_in)

    CurveCryptoSwap(ZAP).exchange(
        CRVTRICRPTO_POOL, 5, 0, weth_in, crv_received, False, SUSHI_POOL
    )

    # swap on sushi and send the amount to msg.sender
    SushiPool(SUSHI_POOL).swap(0, weth_received, msg.sender, b"")


@external
def arbitrage_sushi(weth_in: uint256):
    """
    @notice Buy crv (low) on sushi and sell (high) on curve
    @dev callable by anyone
    """
    reserve_0: uint256 = 0
    reserve_1: uint256 = 0
    timestamp_last: uint256 = 0

    # ---- check we will we receive more than we input ----

    reserve_0, reserve_1, timestamp_last = SushiPool(SUSHI_POOL).getReserves()
    crv_received: uint256 = self.get_amount_out(weth_in, reserve_1, reserve_0)

    weth_received: uint256 = CurveCryptoSwap(ZAP).get_dy(CRVTRICRPTO_POOL, 0, 5, weth_in)

    # if we will receive less than we put in, we cannot arbitrage:
    assert weth_received > weth_in
    
    # ---- execute the arbitrage ----

    # perform sushi swap
    ERC20(WETH).transferFrom(msg.sender, SUSHI_POOL, weth_in)
    SushiPool(SUSHI_POOL).swap(0, weth_in, self, b"")

    # perform curve swap and send to msg.sender
    ERC20(CRV).approve(ZAP, weth_in)
    CurveCryptoSwap(ZAP).exchange(
        CRVTRICRPTO_POOL, 0, 5, crv_received, weth_received, False, SUSHI_POOL
    )


@external
def withdraw_token(_token: address, _amount: uint256):
    """
    @dev Safety function
    """
    assert msg.sender == self.owner  # dev: only owner
    assert ERC20(_token).transfer(msg.sender, _amount)  # dev: failed transfer