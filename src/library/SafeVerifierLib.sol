// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

library SafeVerifierLib {
    error SafeSetupIncomplete();

    /**
     * Verify that the safe has proper guardrails setup. Reverts if not.
     * @param safeAddress address of safe
     */
    function verify(address safeAddress) external {
        // TODO check for guard

        bool isVerified = true;
        if (!isVerified) revert SafeSetupIncomplete();
    }
}
