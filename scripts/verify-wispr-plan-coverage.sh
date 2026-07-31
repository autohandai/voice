#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname -- "$script_directory")
plan_directory="$repository_root/docs/plans"
inventory="$plan_directory/wispr-flow-source-inventory.md"
product="$plan_directory/wispr-flow-parity-product-spec.md"
delivery="$plan_directory/wispr-flow-parity-delivery-plan.md"
expected_count=55

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/autohand-voice-plan-coverage.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

inventory_ids="$temporary_directory/inventory.txt"
product_ids="$temporary_directory/product.txt"
delivery_ids="$temporary_directory/delivery.txt"

sed -n 's/^#### `\(WF-[^`]*\)`.*/\1/p' "$inventory" > "$inventory_ids"
grep -Eo 'WF-[0-9]{8}-(DESKTOP|ANDROID|IOS)-[0-9]{2}' "$product" > "$product_ids"
sed -n 's/^| `\(WF-[^`]*\)`.*/\1/p' "$delivery" > "$delivery_ids"

assert_unique() {
    name=$1
    path=$2
    duplicates=$(sort "$path" | uniq -d)
    if [ -n "$duplicates" ]; then
        echo "$name contains duplicate source IDs:" >&2
        echo "$duplicates" >&2
        exit 1
    fi
}

assert_unique "Inventory" "$inventory_ids"
assert_unique "Delivery plan" "$delivery_ids"

inventory_count=$(wc -l < "$inventory_ids" | tr -d ' ')
delivery_count=$(wc -l < "$delivery_ids" | tr -d ' ')
if [ "$inventory_count" -ne "$expected_count" ]; then
    echo "Inventory has $inventory_count source IDs; expected $expected_count." >&2
    exit 1
fi
if [ "$delivery_count" -ne "$expected_count" ]; then
    echo "Delivery plan has $delivery_count source IDs; expected $expected_count." >&2
    exit 1
fi

sort -u "$inventory_ids" > "$temporary_directory/inventory.sorted"
sort -u "$product_ids" > "$temporary_directory/product.sorted"
sort -u "$delivery_ids" > "$temporary_directory/delivery.sorted"

if ! diff -u "$temporary_directory/inventory.sorted" "$temporary_directory/product.sorted"; then
    echo "Product spec source coverage differs from the inventory." >&2
    exit 1
fi
if ! diff -u "$temporary_directory/inventory.sorted" "$temporary_directory/delivery.sorted"; then
    echo "Delivery plan source coverage differs from the inventory." >&2
    exit 1
fi

echo "Wispr parity plan coverage verified: $expected_count source families."
