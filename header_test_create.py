import sys
import hashlib

def double_sha256(header_bytes):
    return hashlib.sha256(hashlib.sha256(header_bytes).digest()).digest()

def update_nonce(header_bytes, nonce):
    # Assumes nonce is in bytes 76-79 (the usual location for 80-byte bitcoin headers)
    # For 640 bits / 80 bytes header, nonce at offset 76-79 (zero-indexed)
    h = bytearray(header_bytes)
    h[76:80] = nonce.to_bytes(4, byteorder='little')   # Bitcoin uses little-endian nonce
    return bytes(h)

def to_little_endian(hexstr):
    # Input: hex string assumed to represent a hash in big-endian
    # Output: hex string of little-endian (reversed byte order)
    b = bytes.fromhex(hexstr)
    return b[::-1].hex()

def main():
    if len(sys.argv) < 3:
        print(f"Usage: python {sys.argv[0]} <num_tests> <header_hex>")
        print("  header_hex should be a 640-bit (160 hex chars) bitcoin block header")
        sys.exit(1)

    num_tests = int(sys.argv[1])
    header_hex = sys.argv[2].strip().lower()
    if len(header_hex) != 160:
        print(f"Error: header_hex must be 160 hex chars (found {len(header_hex)})")
        sys.exit(1)

    header_bytes = bytes.fromhex(header_hex)

    with open('bitcoin_header.hex', 'w') as f_header, open('bitcoin_hash.hex', 'w') as f_hash:
        for nonce in range(num_tests):
            test_header = update_nonce(header_bytes, nonce)
            f_header.write(test_header.hex() + '\n')
            hash_out = double_sha256(test_header)
            # Convert hash to little-endian format before writing
            hash_le = hash_out[::-1].hex()
            f_hash.write(hash_le + '\n')
    print(f"Created {num_tests} tests (bitcoin_header.hex, bitcoin_hash.hex)")

if __name__ == '__main__':
    main()