// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { BaseIntegrationTest } from "../BaseIntegrationTest.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { FixedAPYAccrual } from "src/yield/FixedAPYAccrual.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccountingToken } from "src/AccountingToken.sol";

abstract contract BaseAccrualIntegrationTest is BaseIntegrationTest {
    FixedAPYAccrual internal accrual;
    address internal constant ALICE = address(0x123);

    function setUp() public override {
        super.setUp();
        address admin = deployment.actors().ADMIN();
        accrual = FixedAPYAccrual(
            address(
                new TransparentUpgradeableProxy(
                    address(new FixedAPYAccrual()),
                    admin,
                    abi.encodeCall(FixedAPYAccrual.initialize, (admin, address(strategy), 0.1e18, block.timestamp))
                )
            )
        );
        vm.startPrank(admin);
        strategy.grantRole(strategy.ALLOCATOR_ROLE(), ALICE);
        AccountingModule(address(accountingModule))
            .grantRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(accrual));
        vm.stopPrank();
        vm.prank(address(deployment.timelock()));
        accountingModule.setCooldownSeconds(0);

        IERC20 asset = IERC20(strategy.asset());
        deal(address(asset), ALICE, 1000e18);
        vm.startPrank(ALICE);
        asset.approve(address(strategy), 1000e18);
        strategy.deposit(1000e18, ALICE);
        vm.stopPrank();
    }
}
