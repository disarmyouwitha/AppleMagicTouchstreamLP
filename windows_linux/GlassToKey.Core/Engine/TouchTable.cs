using System;
using System.Runtime.CompilerServices;

namespace GlassToKey;

internal struct TouchTable<TValue> where TValue : struct
{
    private const byte SlotEmpty = 0;
    private const byte SlotOccupied = 1;
    private const byte SlotTombstone = 2;

    private ulong[] _keys;
    private TValue[] _values;
    private byte[] _states;
    private int _count;
    private int _tombstones;

    public TouchTable(int minimumCapacity = 16)
    {
        int capacity = NextPowerOfTwo(Math.Max(16, minimumCapacity));
        _keys = new ulong[capacity];
        _values = new TValue[capacity];
        _states = new byte[capacity];
        _count = 0;
        _tombstones = 0;
    }

    public int Count => _count;
    public int Capacity => _keys.Length;
    public bool IsEmpty => _count == 0;

    public readonly bool TryGetValue(ulong key, out TValue value)
    {
        int index = FindIndex(key);
        if (index < 0)
        {
            value = default;
            return false;
        }

        value = _values[index];
        return true;
    }

    public readonly bool ContainsKey(ulong key)
    {
        return FindIndex(key) >= 0;
    }

    public ref TValue GetOrAddValueRef(ulong key, out bool exists)
    {
        EnsureCapacity(_count + 1);
        int mask = _keys.Length - 1;
        int index = HashIndex(key, mask);
        int firstTombstone = -1;
        while (true)
        {
            byte state = _states[index];
            if (state == SlotEmpty)
            {
                int insertIndex = firstTombstone >= 0 ? firstTombstone : index;
                _keys[insertIndex] = key;
                _values[insertIndex] = default;
                _states[insertIndex] = SlotOccupied;
                _count++;
                if (firstTombstone >= 0)
                {
                    _tombstones--;
                }

                exists = false;
                return ref _values[insertIndex];
            }

            if (state == SlotOccupied)
            {
                if (_keys[index] == key)
                {
                    exists = true;
                    return ref _values[index];
                }
            }
            else if (firstTombstone < 0)
            {
                firstTombstone = index;
            }

            index = (index + 1) & mask;
        }
    }

    public void Set(ulong key, in TValue value)
    {
        ref TValue slot = ref GetOrAddValueRef(key, out _);
        slot = value;
    }

    public bool Remove(ulong key, out TValue value)
    {
        int index = FindIndex(key);
        if (index < 0)
        {
            value = default;
            return false;
        }

        value = _values[index];
        _values[index] = default;
        _states[index] = SlotTombstone;
        _count--;
        _tombstones++;
        return true;
    }

    public void RemoveAll(bool keepCapacity = true)
    {
        if (!keepCapacity)
        {
            this = new TouchTable<TValue>(16);
            return;
        }

        Array.Clear(_states, 0, _states.Length);
        Array.Clear(_values, 0, _values.Length);
        _count = 0;
        _tombstones = 0;
    }

    public readonly bool IsOccupiedAt(int index)
    {
        return (uint)index < (uint)_states.Length && _states[index] == SlotOccupied;
    }

    public readonly ulong KeyAt(int index)
    {
        return _keys[index];
    }

    public ref TValue ValueRefAt(int index)
    {
        return ref _values[index];
    }

    private readonly int FindIndex(ulong key)
    {
        if (_keys.Length == 0)
        {
            return -1;
        }

        int mask = _keys.Length - 1;
        int index = HashIndex(key, mask);
        while (true)
        {
            byte state = _states[index];
            if (state == SlotEmpty)
            {
                return -1;
            }

            if (state == SlotOccupied && _keys[index] == key)
            {
                return index;
            }

            index = (index + 1) & mask;
        }
    }

    private void EnsureCapacity(int desiredCount)
    {
        int capacity = _keys.Length;
        if (capacity == 0)
        {
            Rehash(16);
            return;
        }

        if (desiredCount * 2 < capacity && (desiredCount + _tombstones) * 2 < capacity)
        {
            return;
        }

        Rehash(capacity * 2);
    }

    private void Rehash(int newCapacity)
    {
        TouchTable<TValue> next = new(newCapacity);
        for (int i = 0; i < _states.Length; i++)
        {
            if (_states[i] != SlotOccupied)
            {
                continue;
            }

            next.Set(_keys[i], _values[i]);
        }

        this = next;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static int HashIndex(ulong key, int mask)
    {
        ulong hashed = key * 11400714819323198485ul;
        return (int)((hashed >> 32) & (uint)mask);
    }

    private static int NextPowerOfTwo(int value)
    {
        int v = value - 1;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        return v + 1;
    }
}
