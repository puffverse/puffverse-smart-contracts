// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IBurnMint {
    /// @notice Mints new tokens for a given address.
    /// @param account The address to mint the new tokens to.
    /// @param amount The number of tokens to be minted.
    /// @dev this function increases the total supply.
    function mint(address account, uint256 amount) external;

    /// @notice Burns tokens from the sender.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(uint256 amount) external;

    /// @notice Burns tokens from a given address..
    /// @param account The address to burn tokens from.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burn(address account, uint256 amount) external;

    /// @notice Burns tokens from a given address..
    /// @param account The address to burn tokens from.
    /// @param amount The number of tokens to be burned.
    /// @dev this function decreases the total supply.
    function burnFrom(address account, uint256 amount) external;
}
