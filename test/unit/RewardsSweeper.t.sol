// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from "@yieldnest-vault/Common.sol";
import { RewardsSweeper } from "src/utils/RewardsSweeper.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockERC721 } from "../mocks/MockERC721.sol";
import { MockAccountingModule } from "../mocks/MockAccountingModule.sol";

contract RewardsSweeperRescueTest is Test {
    address public PROXY_ADMIN = address(0xa1a1a1);
    address public ADMIN = address(0xd34db33f);
    address public RESCUER = address(0x1ece0e1);
    address public BOB = address(0x0b0b);
    address public RECIPIENT = address(0x1ec1);

    bytes32 public ASSET_RESCUER_ROLE;
    bytes32 public REWARDS_SWEEPER_ROLE;
    bytes32 public DEFAULT_ADMIN_ROLE;

    RewardsSweeper public rewardsSweeper;
    MockERC20 public mockToken;
    MockERC20 public mockToken2;
    MockERC721 public mockNFT;
    MockAccountingModule public mockAccountingModule;

    function setUp() public {
        mockToken = new MockERC20("Mock Token", "MOCK", 18);
        mockToken2 = new MockERC20("Mock Token 2", "MOCK2", 6);
        mockNFT = new MockERC721("Mock NFT", "MNFT");
        mockAccountingModule = new MockAccountingModule(address(mockToken));

        RewardsSweeper impl = new RewardsSweeper();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            PROXY_ADMIN,
            abi.encodeWithSelector(RewardsSweeper.initialize.selector, ADMIN, address(mockAccountingModule))
        );
        rewardsSweeper = RewardsSweeper(address(proxy));

        // Cache role constants to avoid prank being consumed by view calls
        ASSET_RESCUER_ROLE = rewardsSweeper.ASSET_RESCUER_ROLE();
        REWARDS_SWEEPER_ROLE = rewardsSweeper.REWARDS_SWEEPER_ROLE();
        DEFAULT_ADMIN_ROLE = rewardsSweeper.DEFAULT_ADMIN_ROLE();

        // Grant ASSET_RESCUER_ROLE to RESCUER
        vm.prank(ADMIN);
        rewardsSweeper.grantRole(ASSET_RESCUER_ROLE, RESCUER);
    }

    // =====================
    // rescueERC20 tests
    // =====================

    function test_rescueERC20_success() public {
        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        assertEq(mockToken.balanceOf(address(rewardsSweeper)), amount);
        assertEq(mockToken.balanceOf(RECIPIENT), 0);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);

        assertEq(mockToken.balanceOf(address(rewardsSweeper)), 0);
        assertEq(mockToken.balanceOf(RECIPIENT), amount);
    }

    function test_rescueERC20_partialAmount() public {
        uint256 totalAmount = 100e18;
        uint256 rescueAmount = 40e18;
        mockToken.mint(address(rewardsSweeper), totalAmount);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, rescueAmount);

        assertEq(mockToken.balanceOf(address(rewardsSweeper)), totalAmount - rescueAmount);
        assertEq(mockToken.balanceOf(RECIPIENT), rescueAmount);
    }

    function test_rescueERC20_differentToken() public {
        uint256 amount = 500e6;
        mockToken2.mint(address(rewardsSweeper), amount);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken2), RECIPIENT, amount);

        assertEq(mockToken2.balanceOf(address(rewardsSweeper)), 0);
        assertEq(mockToken2.balanceOf(RECIPIENT), amount);
    }

    function test_rescueERC20_emitsEvent() public {
        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        vm.expectEmit(true, true, false, true);
        emit RewardsSweeper.ERC20Rescued(address(mockToken), RECIPIENT, amount);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);
    }

    function test_rescueERC20_revertIfNotRescuer() public {
        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, ASSET_RESCUER_ROLE)
        );
        vm.prank(BOB);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);
    }

    function test_rescueERC20_revertIfRewardsSweeperRoleNotSufficient() public {
        address sweeper = address(0x5ee9);
        vm.prank(ADMIN);
        rewardsSweeper.grantRole(REWARDS_SWEEPER_ROLE, sweeper);

        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sweeper, ASSET_RESCUER_ROLE
            )
        );
        vm.prank(sweeper);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);
    }

    function test_rescueERC20_revertIfAdminRoleNotSufficient() public {
        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, ASSET_RESCUER_ROLE)
        );
        vm.prank(ADMIN);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);
    }

    function test_rescueERC20_revertIfInsufficientBalance() public {
        vm.prank(RESCUER);
        vm.expectRevert();
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, 1e18);
    }

    function testFuzz_rescueERC20(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        mockToken.mint(address(rewardsSweeper), amount);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);

        assertEq(mockToken.balanceOf(address(rewardsSweeper)), 0);
        assertEq(mockToken.balanceOf(RECIPIENT), amount);
    }

    // =====================
    // rescueERC721 tests
    // =====================

    function test_rescueERC721_success() public {
        uint256 tokenId = mockNFT.mint(address(rewardsSweeper));

        assertEq(mockNFT.ownerOf(tokenId), address(rewardsSweeper));

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);

        assertEq(mockNFT.ownerOf(tokenId), RECIPIENT);
    }

    function test_rescueERC721_multipleNFTs() public {
        uint256 tokenId1 = mockNFT.mint(address(rewardsSweeper));
        uint256 tokenId2 = mockNFT.mint(address(rewardsSweeper));
        uint256 tokenId3 = mockNFT.mint(address(rewardsSweeper));

        // Rescue only one, others remain
        vm.prank(RESCUER);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId2);

        assertEq(mockNFT.ownerOf(tokenId1), address(rewardsSweeper));
        assertEq(mockNFT.ownerOf(tokenId2), RECIPIENT);
        assertEq(mockNFT.ownerOf(tokenId3), address(rewardsSweeper));
    }

    function test_rescueERC721_emitsEvent() public {
        uint256 tokenId = mockNFT.mint(address(rewardsSweeper));

        vm.expectEmit(true, true, false, true);
        emit RewardsSweeper.ERC721Rescued(address(mockNFT), RECIPIENT, tokenId);

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);
    }

    function test_rescueERC721_revertIfNotRescuer() public {
        uint256 tokenId = mockNFT.mint(address(rewardsSweeper));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, ASSET_RESCUER_ROLE)
        );
        vm.prank(BOB);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);
    }

    function test_rescueERC721_revertIfRewardsSweeperRoleNotSufficient() public {
        address sweeper = address(0x5ee9);
        vm.prank(ADMIN);
        rewardsSweeper.grantRole(REWARDS_SWEEPER_ROLE, sweeper);

        uint256 tokenId = mockNFT.mint(address(rewardsSweeper));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, sweeper, ASSET_RESCUER_ROLE
            )
        );
        vm.prank(sweeper);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);
    }

    function test_rescueERC721_revertIfTokenNotOwned() public {
        uint256 tokenId = mockNFT.mint(BOB); // Mint to BOB, not sweeper

        vm.prank(RESCUER);
        vm.expectRevert();
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);
    }

    function testFuzz_rescueERC721(uint256 tokenId) public {
        mockNFT.mint(address(rewardsSweeper), tokenId);

        assertEq(mockNFT.ownerOf(tokenId), address(rewardsSweeper));

        vm.prank(RESCUER);
        rewardsSweeper.rescueERC721(address(mockNFT), RECIPIENT, tokenId);

        assertEq(mockNFT.ownerOf(tokenId), RECIPIENT);
    }

    // =====================
    // Role management tests
    // =====================

    function test_adminCanGrantRescuerRole() public {
        address newRescuer = address(0xabc);

        vm.prank(ADMIN);
        rewardsSweeper.grantRole(ASSET_RESCUER_ROLE, newRescuer);

        assertTrue(rewardsSweeper.hasRole(ASSET_RESCUER_ROLE, newRescuer));
    }

    function test_adminCanRevokeRescuerRole() public {
        vm.prank(ADMIN);
        rewardsSweeper.revokeRole(ASSET_RESCUER_ROLE, RESCUER);

        assertFalse(rewardsSweeper.hasRole(ASSET_RESCUER_ROLE, RESCUER));
    }

    function test_revokedRescuerCannotRescue() public {
        vm.prank(ADMIN);
        rewardsSweeper.revokeRole(ASSET_RESCUER_ROLE, RESCUER);

        uint256 amount = 100e18;
        mockToken.mint(address(rewardsSweeper), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, RESCUER, ASSET_RESCUER_ROLE
            )
        );
        vm.prank(RESCUER);
        rewardsSweeper.rescueERC20(address(mockToken), RECIPIENT, amount);
    }

    function test_nonAdminCannotGrantRescuerRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, DEFAULT_ADMIN_ROLE
            )
        );
        vm.prank(BOB);
        rewardsSweeper.grantRole(ASSET_RESCUER_ROLE, BOB);
    }
}
