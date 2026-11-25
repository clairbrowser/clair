// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/clair_order_key.h"

#include <optional>
#include <string>
#include <string_view>

namespace clair {

namespace {

// The digits, in the order their bytes sort.
constexpr std::string_view kDigits =
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
constexpr int kBase = 62;
constexpr char kZero = '0';
constexpr char kLast = 'z';
// The smallest integer part, "A" and 26 zeros. A key needs a fraction after
// it, so there is always a key before every other.
constexpr size_t kSmallestLength = 27;

int DigitValue(char c) {
  const size_t at = kDigits.find(c);
  return at == std::string_view::npos ? -1 : static_cast<int>(at);
}

char Digit(int value) {
  return kDigits[static_cast<size_t>(value)];
}

bool IsSmallestInteger(std::string_view integer) {
  return integer.size() == kSmallestLength && integer[0] == 'A' &&
         integer.substr(1).find_first_not_of(kZero) == std::string_view::npos;
}

// The length of an integer part starting with `head`: "a" to "z" make 2 to
// 27 characters, "Z" to "A" the same downwards. Zero for any other head.
size_t IntegerLength(char head) {
  if (head >= 'a' && head <= 'z') {
    return static_cast<size_t>(head - 'a') + 2;
  }
  if (head >= 'A' && head <= 'Z') {
    return static_cast<size_t>('Z' - head) + 2;
  }
  return 0;
}

// The key's integer part, or nothing when the key is too short for it.
std::optional<std::string_view> IntegerPart(std::string_view key) {
  const size_t length = key.empty() ? 0 : IntegerLength(key[0]);
  if (length == 0 || length > key.size()) {
    return std::nullopt;
  }
  return key.substr(0, length);
}

// A fraction between the fractions `a` and `b`, each without trailing zeros,
// `a` sorting before `b`; no `b` means 1, and an empty `a` 0.
std::string Midpoint(std::string_view a, std::optional<std::string_view> b) {
  if (b) {
    // The digits both share, `a` padded with zeros.
    size_t n = 0;
    while (n < b->size() && (n < a.size() ? a[n] : kZero) == (*b)[n]) {
      ++n;
    }
    if (n == b->size()) {
      return std::string();
    }
    if (n > 0) {
      return std::string(b->substr(0, n)) +
             Midpoint(n < a.size() ? a.substr(n) : std::string_view(),
                      b->substr(n));
    }
  }
  // The first digits differ.
  const int digit_a = a.empty() ? 0 : DigitValue(a[0]);
  const int digit_b = b ? DigitValue((*b)[0]) : kBase;
  if (digit_b - digit_a > 1) {
    // Halfway, rounding up.
    return std::string(1, Digit((digit_a + digit_b + 1) / 2));
  }
  // Neighbouring digits: `b`'s first digit alone sorts between them when `b`
  // goes on, or else a digit more after `a`'s.
  if (b && b->size() > 1) {
    return std::string(1, (*b)[0]);
  }
  return std::string(1, Digit(digit_a)) +
         Midpoint(a.size() > 1 ? a.substr(1) : std::string_view(),
                  std::nullopt);
}

// The integer part after `integer`, or nothing after the largest.
std::optional<std::string> IncrementInteger(std::string_view integer) {
  const char head = integer[0];
  std::string digits(integer.substr(1));
  bool carry = true;
  for (size_t i = digits.size(); carry && i > 0; --i) {
    const int value = DigitValue(digits[i - 1]) + 1;
    if (value == kBase) {
      digits[i - 1] = kZero;
    } else {
      digits[i - 1] = Digit(value);
      carry = false;
    }
  }
  if (!carry) {
    return std::string(1, head) + digits;
  }
  if (head == 'Z') {
    return std::string("a") + kZero;
  }
  if (head == 'z') {
    return std::nullopt;
  }
  const char next = static_cast<char>(head + 1);
  // Lowercase heads grow longer, uppercase ones shorter.
  if (next > 'a') {
    digits.push_back(kZero);
  } else {
    digits.pop_back();
  }
  return std::string(1, next) + digits;
}

// The integer part before `integer`, or nothing before the smallest.
std::optional<std::string> DecrementInteger(std::string_view integer) {
  const char head = integer[0];
  std::string digits(integer.substr(1));
  bool borrow = true;
  for (size_t i = digits.size(); borrow && i > 0; --i) {
    const int value = DigitValue(digits[i - 1]) - 1;
    if (value < 0) {
      digits[i - 1] = kLast;
    } else {
      digits[i - 1] = Digit(value);
      borrow = false;
    }
  }
  if (!borrow) {
    return std::string(1, head) + digits;
  }
  if (head == 'a') {
    return std::string("Z") + kLast;
  }
  if (head == 'A') {
    return std::nullopt;
  }
  const char previous = static_cast<char>(head - 1);
  if (previous < 'Z') {
    digits.push_back(kLast);
  } else {
    digits.pop_back();
  }
  return std::string(1, previous) + digits;
}

}  // namespace

bool IsValidOrderKey(std::string_view key) {
  const std::optional<std::string_view> integer = IntegerPart(key);
  if (!integer || IsSmallestInteger(key)) {
    return false;
  }
  for (char c : key.substr(1)) {
    if (DigitValue(c) < 0) {
      return false;
    }
  }
  const std::string_view fraction = key.substr(integer->size());
  return fraction.empty() || fraction.back() != kZero;
}

std::string OrderKeyBetween(std::string_view before, std::string_view after) {
  if ((!before.empty() && !IsValidOrderKey(before)) ||
      (!after.empty() && !IsValidOrderKey(after)) ||
      (!before.empty() && !after.empty() && before >= after)) {
    return std::string();
  }
  if (before.empty()) {
    if (after.empty()) {
      return std::string("a") + kZero;
    }
    const std::string_view integer = *IntegerPart(after);
    const std::string_view fraction = after.substr(integer.size());
    if (IsSmallestInteger(integer)) {
      return std::string(integer) + Midpoint(std::string_view(), fraction);
    }
    // With a fraction, its integer part alone sorts before it.
    if (integer.size() < after.size()) {
      return std::string(integer);
    }
    return DecrementInteger(integer).value_or(std::string());
  }
  const std::string_view integer_before = *IntegerPart(before);
  const std::string_view fraction_before = before.substr(integer_before.size());
  if (after.empty()) {
    std::optional<std::string> next = IncrementInteger(integer_before);
    return next ? *next
                : std::string(integer_before) +
                      Midpoint(fraction_before, std::nullopt);
  }
  const std::string_view integer_after = *IntegerPart(after);
  const std::string_view fraction_after = after.substr(integer_after.size());
  if (integer_before == integer_after) {
    return std::string(integer_before) +
           Midpoint(fraction_before, fraction_after);
  }
  std::optional<std::string> next = IncrementInteger(integer_before);
  if (!next) {
    return std::string();
  }
  if (std::string_view(*next) < after) {
    return *next;
  }
  return std::string(integer_before) + Midpoint(fraction_before, std::nullopt);
}

}  // namespace clair
