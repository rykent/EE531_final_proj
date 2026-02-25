import sys
import os

def parse_rsp_file(rsp_filename):
    # Extracts tests as list of dicts: {'Len': int, 'Msg': str, 'MD': str}
    tests = []
    current = {}
    with open(rsp_filename, 'r') as f:
        for line in f:
            l = line.strip()
            if l.startswith('Len ='):
                if current:
                    tests.append(current)
                    current = {}
                current['Len'] = int(l.split('=')[1].strip())
            elif l.startswith('Msg ='):
                current['Msg'] = l.split('=')[1].strip()
            elif l.startswith('MD ='):
                current['MD'] = l.split('=')[1].strip()
        if current:
            tests.append(current)
    return tests

def sha256_pad(msghex, msg_len_bits):
    # Actual message = first msg_len_bits of Msg (big-endian bit order within each byte).
    # Then SHA-256 padding: append 1, zeros until ≡ 448 (mod 512), then 64-bit length.
    msg_bytes = bytearray.fromhex(msghex)
    # Build bit list, MSB first within each byte; take first msg_len_bits only
    bits = []
    for byte in msg_bytes:
        for shift in range(7, -1, -1):
            bits.append((byte >> shift) & 1)
    bits = bits[:msg_len_bits]
    # Append padding bit '1'
    bits.append(1)
    # Zeros until length in bits ≡ 448 (mod 512)
    while len(bits) % 512 != 448:
        bits.append(0)
    # Append original length as 64-bit big-endian
    for i in range(64):
        bits.append((msg_len_bits >> (63 - i)) & 1)
    # Pack bits into bytes (8 per byte, MSB first)
    out = bytearray()
    for i in range(0, len(bits), 8):
        b = 0
        for j in range(8):
            b = (b << 1) | (bits[i + j] if i + j < len(bits) else 0)
        out.append(b)
    return out.hex()

def main():
    if len(sys.argv) < 2:
        print(f"Usage: python {os.path.basename(sys.argv[0])} <input.rsp>")
        sys.exit(1)
    rsp_filename = sys.argv[1]
    tests = parse_rsp_file(rsp_filename)

    count = 0
    with open('test_message.hex', 'w') as f_msg, open('test_hash.hex', 'w') as f_hash:
        for test in tests:
            msglen = test['Len']
            # Padded block = msg + 0x80 + zeros + 64-bit length. Single 512-bit block
            # only when msg + 1 + 64 <= 512 and (msg+1+zeros) ≡ 448 (mod 512), i.e. msg <= 440 bits.
            if msglen > 440:
                continue  # Skip so padded message fits in one 512-bit block
            msghex = test['Msg']
            padded_msg = sha256_pad(msghex, msglen)
            if len(padded_msg) != 128:  # 512 bits = 64 bytes = 128 hex chars
                continue
            f_msg.write(padded_msg + '\n')
            f_hash.write(test['MD'] + '\n')
            count += 1
    print(f"Created {count} tests (test_message.hex, test_hash.hex)")

if __name__ == '__main__':
    main()