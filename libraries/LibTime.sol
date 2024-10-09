// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/Strings.sol";

//From: https://etherscan.io/address/0x23d23d8f243e57d0b924bff3a3191078af325101#code
library LibTime {

    using Strings for uint256;
    using Strings for uint;

    uint constant SECONDS_PER_DAY = 24 * 60 * 60;
    int constant OFFSET19700101 = 2440588;

    string constant ZERO = '0';

    function _daysToDate(uint _days) internal pure returns (uint year, uint month, uint day) {
        int __days = int(_days);

        int L = __days + 68569 + OFFSET19700101;
        int N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int _month = 80 * L / 2447;
        int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint(_year);
        month = uint(_month);
        day = uint(_day);
    }

    // YYYY/MM/DD 2022/02/26(UTC)
    function timestampToDateStr(uint timestamp) internal pure returns (string memory){
        (uint year, uint month,uint day) = _daysToDate(timestamp / SECONDS_PER_DAY);


        string[5] memory parts;
        parts[0] = string(abi.encodePacked(year.toString(), '/'));
        if(month < 10){
            parts[1] = string(abi.encodePacked(ZERO, month.toString()));
        }else{
            parts[1] = month.toString();
        }
        parts[2] = '/';

        if(day < 10){
            parts[3] = string(abi.encodePacked(ZERO, day.toString()));
        }else{
            parts[3] = day.toString();
        }
        parts[4] = '(UTC)';

        return string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4]));
    }
}
