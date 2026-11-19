using System;
using System.Collections.Generic;
using System.Text;

namespace RoyalRun.Net
{
    // A small QR code generator with no external libraries (Unity has no built-in one).
    // It does what is needed for an address like http://192.168.1.5:8080:
    // byte mode, error-correction level M, versions 1-3 (up to 42 characters).
    // The file does not use Unity - it can be tested separately from the editor.
    public static class QrCode
    {
        // version -> number of data bytes and number of correction bytes (one block, level M)
        static readonly int[] DataCodewords = { 0, 16, 28, 44 };
        static readonly int[] EccCodewords = { 0, 10, 16, 26 };

        public const int MaxBytes = 42;

        // Returns the module matrix [row, column] (true = dark) or null if the text is too long.
        public static bool[,] Encode(string text)
        {
            byte[] data = Encoding.UTF8.GetBytes(text);

            int version = 0;
            for (int v = 1; v <= 3; v++)
            {
                if (data.Length <= (DataCodewords[v] * 8 - 12) / 8) { version = v; break; }
            }
            if (version == 0) return null;

            byte[] codewords = BuildCodewords(data, version);
            int size = 17 + 4 * version;

            bool[,] modules = new bool[size, size];
            bool[,] isFunction = new bool[size, size];
            DrawFunctionPatterns(modules, isFunction, version);
            DrawData(modules, isFunction, codewords);

            // pick the mask with the lowest penalty
            int bestMask = 0;
            int bestPenalty = int.MaxValue;
            for (int mask = 0; mask < 8; mask++)
            {
                ApplyMask(modules, isFunction, mask);
                DrawFormatBits(modules, isFunction, mask);
                int penalty = Penalty(modules);
                if (penalty < bestPenalty) { bestPenalty = penalty; bestMask = mask; }
                ApplyMask(modules, isFunction, mask);   // XOR a second time = remove the mask
            }
            ApplyMask(modules, isFunction, bestMask);
            DrawFormatBits(modules, isFunction, bestMask);
            return modules;
        }

        // ---------- data and error correction ----------

        static byte[] BuildCodewords(byte[] data, int version)
        {
            int dataCount = DataCodewords[version];
            List<bool> bits = new List<bool>();
            AppendBits(bits, 0x4, 4);               // "byte" mode
            AppendBits(bits, data.Length, 8);       // length
            foreach (byte b in data) AppendBits(bits, b, 8);

            int capacityBits = dataCount * 8;
            for (int i = 0; i < 4 && bits.Count < capacityBits; i++) bits.Add(false);   // terminator
            while (bits.Count % 8 != 0) bits.Add(false);

            byte[] result = new byte[dataCount + EccCodewords[version]];
            for (int i = 0; i < bits.Count; i++)
                if (bits[i]) result[i / 8] |= (byte)(0x80 >> (i % 8));

            int pad = 0xEC;
            for (int i = bits.Count / 8; i < dataCount; i++)
            {
                result[i] = (byte)pad;
                pad ^= 0xEC ^ 0x11;
            }

            byte[] ecc = ReedSolomon(result, dataCount, EccCodewords[version]);
            Array.Copy(ecc, 0, result, dataCount, ecc.Length);
            return result;
        }

        static void AppendBits(List<bool> bits, int value, int count)
        {
            for (int i = count - 1; i >= 0; i--) bits.Add(((value >> i) & 1) != 0);
        }

        static byte[] ReedSolomon(byte[] data, int dataLen, int eccLen)
        {
            // generator polynomial of degree eccLen
            byte[] gen = new byte[eccLen];
            gen[eccLen - 1] = 1;
            int root = 1;
            for (int i = 0; i < eccLen; i++)
            {
                for (int j = 0; j < eccLen; j++)
                {
                    gen[j] = Multiply(gen[j], root);
                    if (j + 1 < eccLen) gen[j] ^= gen[j + 1];
                }
                root = Multiply(root, 0x02);
            }

            byte[] rem = new byte[eccLen];
            for (int i = 0; i < dataLen; i++)
            {
                int factor = data[i] ^ rem[0];
                Array.Copy(rem, 1, rem, 0, eccLen - 1);
                rem[eccLen - 1] = 0;
                for (int j = 0; j < eccLen; j++) rem[j] ^= Multiply(gen[j], factor);
            }
            return rem;
        }

        static byte Multiply(int x, int y)
        {
            int z = 0;
            for (int i = 7; i >= 0; i--)
            {
                z = (z << 1) ^ ((z >> 7) * 0x11D);
                z ^= ((y >> i) & 1) * x;
            }
            return (byte)z;
        }

        // ---------- drawing ----------

        static void SetFunction(bool[,] m, bool[,] f, int x, int y, bool dark)
        {
            m[y, x] = dark;
            f[y, x] = true;
        }

        static void DrawFunctionPatterns(bool[,] m, bool[,] f, int version)
        {
            int size = m.GetLength(0);

            // timing patterns
            for (int i = 0; i < size; i++)
            {
                SetFunction(m, f, 6, i, i % 2 == 0);
                SetFunction(m, f, i, 6, i % 2 == 0);
            }

            // three large squares in the corners (with their white border)
            DrawFinder(m, f, 3, 3);
            DrawFinder(m, f, size - 4, 3);
            DrawFinder(m, f, 3, size - 4);

            // alignment square (versions 2 and 3 have just one)
            if (version >= 2)
            {
                int c = size - 7;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++)
                        SetFunction(m, f, c + dx, c + dy, Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1);
            }

            // space for the format bits (filled in later)
            DrawFormatBits(m, f, 0);
        }

        static void DrawFinder(bool[,] m, bool[,] f, int cx, int cy)
        {
            int size = m.GetLength(0);
            for (int dy = -4; dy <= 4; dy++)
            {
                for (int dx = -4; dx <= 4; dx++)
                {
                    int dist = Math.Max(Math.Abs(dx), Math.Abs(dy));
                    int x = cx + dx, y = cy + dy;
                    if (x >= 0 && x < size && y >= 0 && y < size)
                        SetFunction(m, f, x, y, dist != 2 && dist != 4);
                }
            }
        }

        // Level M has code 00; format = 5 data bits + 10 BCH correction bits, then XOR with 0x5412.
        static void DrawFormatBits(bool[,] m, bool[,] f, int mask)
        {
            int size = m.GetLength(0);
            int data = (0 << 3) | mask;
            int rem = data;
            for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
            int bits = ((data << 10) | rem) ^ 0x5412;

            for (int i = 0; i <= 5; i++) SetFunction(m, f, 8, i, GetBit(bits, i));
            SetFunction(m, f, 8, 7, GetBit(bits, 6));
            SetFunction(m, f, 8, 8, GetBit(bits, 7));
            SetFunction(m, f, 7, 8, GetBit(bits, 8));
            for (int i = 9; i < 15; i++) SetFunction(m, f, 14 - i, 8, GetBit(bits, i));

            for (int i = 0; i < 8; i++) SetFunction(m, f, size - 1 - i, 8, GetBit(bits, i));
            for (int i = 8; i < 15; i++) SetFunction(m, f, 8, size - 15 + i, GetBit(bits, i));
            SetFunction(m, f, 8, size - 8, true);   // always a dark module
        }

        static bool GetBit(int value, int i)
        {
            return ((value >> i) & 1) != 0;
        }

        static void DrawData(bool[,] m, bool[,] f, byte[] codewords)
        {
            int size = m.GetLength(0);
            int bitIndex = 0;
            int totalBits = codewords.Length * 8;

            // walk pairs of columns from right to left, snaking up and down
            for (int right = size - 1; right >= 1; right -= 2)
            {
                if (right == 6) right = 5;   // column six is taken by the timing pattern
                for (int vert = 0; vert < size; vert++)
                {
                    for (int j = 0; j < 2; j++)
                    {
                        int x = right - j;
                        bool upward = ((right + 1) & 2) == 0;
                        int y = upward ? size - 1 - vert : vert;
                        if (f[y, x]) continue;

                        bool dark = false;
                        if (bitIndex < totalBits)
                        {
                            dark = ((codewords[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1) != 0;
                            bitIndex++;
                        }
                        m[y, x] = dark;
                    }
                }
            }
        }

        static void ApplyMask(bool[,] m, bool[,] f, int mask)
        {
            int size = m.GetLength(0);
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    if (f[y, x]) continue;
                    bool invert;
                    switch (mask)
                    {
                        case 0: invert = (x + y) % 2 == 0; break;
                        case 1: invert = y % 2 == 0; break;
                        case 2: invert = x % 3 == 0; break;
                        case 3: invert = (x + y) % 3 == 0; break;
                        case 4: invert = (x / 3 + y / 2) % 2 == 0; break;
                        case 5: invert = x * y % 2 + x * y % 3 == 0; break;
                        case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0; break;
                        default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0; break;
                    }
                    if (invert) m[y, x] = !m[y, x];
                }
            }
        }

        // penalty for "bad" patterns: long runs, 2x2 blocks, patterns that look like a corner square, imbalance of black and white
        static int Penalty(bool[,] m)
        {
            int size = m.GetLength(0);
            int penalty = 0;

            for (int a = 0; a < size; a++)
            {
                int runRow = 1, runCol = 1;
                for (int b = 1; b < size; b++)
                {
                    if (m[a, b] == m[a, b - 1]) { runRow++; if (runRow == 5) penalty += 3; else if (runRow > 5) penalty++; }
                    else runRow = 1;
                    if (m[b, a] == m[b - 1, a]) { runCol++; if (runCol == 5) penalty += 3; else if (runCol > 5) penalty++; }
                    else runCol = 1;
                }
            }

            for (int y = 0; y < size - 1; y++)
                for (int x = 0; x < size - 1; x++)
                    if (m[y, x] == m[y, x + 1] && m[y, x] == m[y + 1, x] && m[y, x] == m[y + 1, x + 1]) penalty += 3;

            bool[] pat1 = { true, false, true, true, true, false, true, false, false, false, false };
            bool[] pat2 = { false, false, false, false, true, false, true, true, true, false, true };
            for (int a = 0; a < size; a++)
            {
                for (int b = 0; b + 11 <= size; b++)
                {
                    bool r1 = true, r2 = true, c1 = true, c2 = true;
                    for (int k = 0; k < 11; k++)
                    {
                        if (m[a, b + k] != pat1[k]) r1 = false;
                        if (m[a, b + k] != pat2[k]) r2 = false;
                        if (m[b + k, a] != pat1[k]) c1 = false;
                        if (m[b + k, a] != pat2[k]) c2 = false;
                    }
                    if (r1) penalty += 40;
                    if (r2) penalty += 40;
                    if (c1) penalty += 40;
                    if (c2) penalty += 40;
                }
            }

            int dark = 0;
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) if (m[y, x]) dark++;
            int total = size * size;
            int k2 = (int)Math.Ceiling(Math.Abs(dark * 20 - total * 10) / (double)total) - 1;
            if (k2 > 0) penalty += k2 * 10;

            return penalty;
        }
    }
}
