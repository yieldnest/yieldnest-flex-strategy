// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseIntegrationTest_6Decimals } from "../../base6decimals/BaseIntegrationTest_6Decimals.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { FixedAPYAccrual } from "src/yield/FixedAPYAccrual.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BaseAccrual6IntegrationTest is BaseIntegrationTest_6Decimals {
    FixedAPYAccrual internal accrual;
    address internal constant ALICE = address(0x777);

    function setUp() public virtual override {
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
        deal(strategy.asset(), ALICE, 2000e6);
        vm.startPrank(ALICE);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(2000e6, ALICE);
        vm.stopPrank();
    }
}
