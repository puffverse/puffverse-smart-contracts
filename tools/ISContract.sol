// SPDX-License-Identifier: MIT

pragma solidity ^0.4.18;

contract ISContract {
    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function isContracts(address []addr) public view returns (address[] memory _addrs) {
        address[] memory addrs = new address[](addr.length);
        uint count = 0;
        for (uint i = 0; i < addr.length; i++) {
            if (isContract(addr[i])){
                addrs[count] = addr[i];
                count +=1;
            }
        }

        _addrs = new address[](count);

        for(i=0;i<count;i++){
            _addrs[i] = addrs[i];
        }
    }
}