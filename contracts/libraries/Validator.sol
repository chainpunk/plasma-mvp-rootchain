pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ECRecovery.sol";

library Validator {
    uint8 constant WORD_SIZE = 32;

    // @param leaf     a leaf of the tree
    // @param index    position of this leaf in the tree that is zero indexed
    // @param rootHash block header of the merkle tree
    // @param proof    sequence of hashes from the leaf to check against the root
    function checkMembership(bytes32 leaf, uint256 index, bytes32 rootHash, bytes proof)
        internal
        pure
        returns (bool)
    {
        // depth 16 merkle tree
        require(proof.length == 512, "Incorrect proof length");

        bytes32 proofElement;
        bytes32 computedHash = leaf;

        for (uint256 i = 32; i <= 512; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }
            if (index % 2 == 0) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
            index = index / 2;
        }
        return computedHash == rootHash;
    }

    // @param txHash      transaction hash
    // @param rootHash    block header of the merkle tree
    // @param input1      indicator for the second input
    // @param sigs        transaction signatures
    // @notice            when one input is present, we require it to be the first input by convention
    function checkSigs(bytes32 txHash, bytes32 confirmationHash, bool input1, bytes sigs, bytes confirmSignatures)
        internal
        pure
        returns (bool)
    {
        require(sigs.length == 130, "two transcation signatures, 65 bytes each, are required");

        bytes memory sig0 = slice(sigs, 0, 65);
        if (input1) {
            require(confirmSignatures.length == 130, "two confirm signatures required with two inputs");
            bytes memory sig1 = slice(sigs, 65, 65);

            // check both input signatures
            address recoveredTx0 = recover(txHash, sig0);
            address recoveredConfirmation0 = recover(confirmationHash, slice(confirmSignatures, 0, 65));

            address recoveredTx1 = recover(txHash, sig1);
            address recoveredConfirmation1 = recover(confirmationHash, slice(confirmSignatures, 65, 65));

            return recoveredTx0 == recoveredConfirmation0 && recoveredTx1 == recoveredConfirmation1 &&
                recoveredTx0 != address(0) && recoveredTx1 != address(0);
        } else {
            // normal case when only one input is present
            require(confirmSignatures.length == 65, "one confirm signatures required with one input");
            address recoveredTx = recover(txHash, sig0);
            address recoveredConfirmation = recover(confirmationHash, confirmSignatures);
            return recoveredTx == recoveredConfirmation && recoveredTx != address(0);
        }
    }

    function recover(bytes32 hash, bytes sig)
        internal
        pure
        returns (address)
    {

        hash = ECRecovery.toEthSignedMessageHash(hash);
        return ECRecovery.recover(hash, sig);
    }

    /* Helpers */

    // @param _bytes raw bytes that needs to be slices
    // @param start  start of the slice relative to `_bytes`
    // @param len    length of the sliced byte array
    function slice(bytes _bytes, uint start, uint len)
            internal
            pure
            returns (bytes)
        {
            require(_bytes.length - start >= len, "slice out of bounds");

            if (_bytes.length == len)
                return _bytes;

            bytes memory result;
            uint src;
            uint dest;
            assembly {
                // memory & free memory pointer
                result := mload(0x40)
                mstore(result, len) // store the size in the prefix
                mstore(0x40, add(result, and(add(add(0x20, len), 0x1f), not(0x1f)))) // padding

                // pointers
                src := add(start, add(0x20, _bytes))
                dest := add(0x20, result)
            }

            // copy as many word sizes as possible
            for(; len >= WORD_SIZE; len -= WORD_SIZE) {
                assembly {
                    mstore(dest, mload(src))
                }

                src += WORD_SIZE;
                dest += WORD_SIZE;
            }

            // copy remaining bytes
            uint mask = 256 ** (WORD_SIZE - len) - 1;
            assembly {
                let srcpart := and(mload(src), not(mask)) // zero out src
                let destpart := and(mload(dest), mask) // retrieve the bytes
                mstore(dest, or(destpart, srcpart))
            }

            return result;
    }
}
