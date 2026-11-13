// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;
import { BaseAccrual6IntegrationTest } from "./BaseAccrual6IntegrationTest.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { AccountingModule, IAccountingModule } from "src/AccountingModule.sol";
import { AccountingToken } from "src/AccountingToken.sol";

contract AccrualRotationIntegrationTest is BaseAccrual6IntegrationTest {
    function _rotate(bool grantRewards, bool switchToken) internal returns (AccountingModule replacement) {
        address admin = deployment.actors().ADMIN();
        replacement = AccountingModule(
            address(
                new TransparentUpgradeableProxy(
                    address(new AccountingModule()),
                    admin,
                    abi.encodeCall(
                        AccountingModule.initialize,
                        (
                            address(strategy),
                            admin,
                            accountingModule.safe(),
                            accountingToken,
                            accountingModule.targetApy(),
                            accountingModule.lowerBound(),
                            1000e6,
                            0
                        )
                    )
                )
            )
        );
        vm.startPrank(admin);
        if (grantRewards) replacement.grantRole(replacement.REWARDS_PROCESSOR_ROLE(), address(accrual));
        strategy.setAccountingModule(address(replacement));
        if (switchToken) AccountingToken(address(accountingToken)).setAccountingModule(address(replacement));
        vm.stopPrank();
    }

    function _testIncompleteRotation(bool missingRole) internal {
        vm.warp(block.timestamp + 1);
        accrual.accrue();
        uint256 fraction = accrual.remainder();
        uint256 checkpoint = accrual.lastAccrual();
        assertGt(fraction, 0);
        vm.warp(block.timestamp + 1 minutes);
        (uint256 pendingBeforeRotation, uint256 fractionBeforeRotation) = accrual.previewAccrual();
        assertGt(pendingBeforeRotation, 0);
        AccountingModule replacement = _rotate(!missingRole, missingRole);
        (uint256 pendingAfterRotation, uint256 fractionAfterRotation) = accrual.previewAccrual();
        assertEq(pendingAfterRotation, pendingBeforeRotation);
        assertEq(fractionAfterRotation, fractionBeforeRotation);
        vm.warp(block.timestamp + 1 days);
        (uint256 expected, uint256 expectedFraction) = accrual.previewAccrual();
        assertGt(expected, 0);
        if (missingRole) {
            vm.expectRevert(
                abi.encodeWithSignature(
                    "AccessControlUnauthorizedAccount(address,bytes32)",
                    address(accrual),
                    replacement.REWARDS_PROCESSOR_ROLE()
                )
            );
        } else {
            vm.expectRevert(AccountingToken.Unauthorized.selector);
        }
        accrual.accrue();
        assertEq(accrual.lastAccrual(), checkpoint);
        assertEq(accrual.remainder(), fraction);
        assertEq(replacement.snapshotsLength(), 1);
        vm.startPrank(deployment.actors().ADMIN());
        if (missingRole) replacement.grantRole(replacement.REWARDS_PROCESSOR_ROLE(), address(accrual));
        else AccountingToken(address(accountingToken)).setAccountingModule(address(replacement));
        vm.stopPrank();
        assertEq(accrual.accrue(), expected);
        assertEq(accrual.remainder(), expectedFraction);
        assertEq(replacement.snapshotsLength(), 2);
    }

    function test_rotationMissingRoleCanBeRepaired() public {
        _testIncompleteRotation(true);
    }

    function test_rotationMissingTokenAuthorityCanBeRepaired() public {
        _testIncompleteRotation(false);
    }
}
