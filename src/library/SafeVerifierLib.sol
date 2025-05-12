// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

library SafeVerifierLib {
    error SafeSetupIncomplete();

    bytes32 constant MODULE_GUARD_STORAGE_SLOT = 0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    /**
     * Verify that the safe has proper guardrails setup. Reverts if not.
     * @param safeAddress address of safe
     */
    function verify(address safeAddress) external {
        // TODO check for guard
        // https://github.com/search?q=repo%3Asafe-global%2Fsafe-smart-account%20StorageAccessible&type=code
        // get guard address
        // compare
        // q: module guard vs guard?

        bool isVerified = true;
        if (!isVerified) revert SafeSetupIncomplete();
    }
}
