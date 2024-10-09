// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/ISvgBuilderClient.sol";
import "../libraries/LibTime.sol";

contract SvgBuilderClient is ISvgBuilderClient {

    using Strings for uint256;
    uint constant DIVIDER = 1e16;

    function buildSvg(uint256 tokenId, uint256 lockAmount, uint256 unlockTime) external pure returns (string memory){

        string memory header = '<svg width="128" height="160" fill="none"    xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#a)">  <rect width="128" height="160" rx="8" fill="url(#b)"/>  <g opacity=".9" filter="url(#c)">  <path d="M-11 68.5s20.5 14 48 14S71 67.3 90.5 58s51.5 4.5 51.5 4.5v105a8 8 0 0 1-8 8H-3a8 8 0 0 1-8-8v-99Z" fill="url(#d)"/>  </g>  <g opacity=".75" fill="#F0F0F5" font-size="8" font-family="PingFang SC">';

        string memory tokenIdText = string(abi.encodePacked('<text x="21" y="111.6">ID ', tokenId.toString(),'</text>'));
        string memory lockAmountText = string(abi.encodePacked('<text x="21" y="124.4">', amountToStr(lockAmount),' APX</text>'));
        string memory unlockTimeText = string(abi.encodePacked('<text x="21" y="137.9">', LibTime.timestampToDateStr(unlockTime),'</text>'));

        string memory bottom = '<svg class="w-[48px] h-[48px] text-gray-800 dark:text-white" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24"><path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 0 0-2 2v4m5-6h8M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m0 0h3a2 2 0 0 1 2 2v4m0 0v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-6m18 0s-4 2-9 2-9-2-9-2m9-2h.01"/></svg>';
        string memory output = string(abi.encodePacked(header, tokenIdText, lockAmountText, unlockTimeText, bottom));
        return output;
    }

    function amountToStr(uint256 lockAmount) public pure returns (string memory){
        uint intPart = lockAmount / (1 ether);
        uint fractionPart = (lockAmount % (1 ether)) / DIVIDER;
        string memory dotPart;
        if(fractionPart >= 10){
            dotPart = '.';
        }else{
            dotPart = '.0';
        }
        return string(abi.encodePacked(intPart.toString(), dotPart, fractionPart.toString()));
    }
}
