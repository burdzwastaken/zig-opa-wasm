package builtin_test

import rego.v1

test_sprintf := sprintf("Hello, %s! You have %d messages.", [input.name, input.count])

test_concat := concat(", ", ["a", "b", "c"])
test_contains := contains("hello world", "world")
test_startswith := startswith("hello world", "hello")
test_endswith := endswith("hello world", "world")
test_indexof := indexof("hello", "l")
test_indexof_n := indexof_n("hello", "l")
test_lower := lower("HELLO")
test_upper := upper("hello")
test_split := split("a,b,c", ",")
test_replace := replace("hello", "l", "L")
test_substring := substring("hello", 1, 3)
test_trim := trim("  hello  ", " ")
test_trim_left := trim_left("  hello", " ")
test_trim_right := trim_right("hello  ", " ")
test_trim_prefix := trim_prefix("hello world", "hello ")
test_trim_suffix := trim_suffix("hello world", " world")
test_trim_space := trim_space("  hello  ")
test_strings_reverse := strings.reverse("hello")

test_abs := abs(-5)
test_round := round(3.7)
test_ceil := ceil(3.2)
test_floor := floor(3.8)
test_sum := sum([1, 2, 3, 4])
test_product := product([2, 3, 4])
test_max := max([1, 5, 3])
test_min := min([1, 5, 3])
test_numbers_range := numbers.range(1, 5)

test_array_concat := array.concat([1, 2], [3, 4])
test_array_slice := array.slice([1, 2, 3, 4, 5], 1, 3)
test_array_reverse := array.reverse([1, 2, 3])
test_sort := sort([3, 1, 2])
test_count_array := count([1, 2, 3])
test_count_string := count("hello")
test_count_object := count({"a": 1, "b": 2})

test_object_get := object.get({"a": 1}, "a", 0)
test_object_get_default := object.get({"a": 1}, "b", 99)
test_object_keys := object.keys({"a": 1, "b": 2})
test_object_remove := object.remove({"a": 1, "b": 2}, ["a"])

test_type_name_string := type_name("hello")
test_type_name_number := type_name(42)
test_type_name_array := type_name([1, 2])
test_type_name_object := type_name({"a": 1})
test_is_string := is_string("hello")
test_is_number := is_number(42)
test_is_boolean := is_boolean(true)
test_is_array := is_array([1, 2])
test_is_object := is_object({"a": 1})
test_is_null := is_null(null)

test_base64_encode := base64.encode("hello")
test_base64_decode := base64.decode("aGVsbG8=")
test_base64url_encode := base64url.encode("hello")
test_base64url_encode_no_pad := base64url.encode_no_pad("hello")
test_base64url_decode := base64url.decode("aGVsbG8")

test_hex_encode := hex.encode("hello")
test_hex_decode := hex.decode("68656c6c6f")

test_urlquery_encode := urlquery.encode("hello world")
test_urlquery_decode := urlquery.decode("hello%20world")

test_crypto_md5 := crypto.md5("hello")
test_crypto_sha1 := crypto.sha1("hello")
test_crypto_sha256 := crypto.sha256("hello")

test_json_is_valid := json.is_valid("{\"a\": 1}")
test_json_marshal := json.marshal({"a": 1})
test_json_unmarshal := json.unmarshal("{\"a\": 1}")

test_time_now_ns := time.now_ns()

test_format_int_binary := format_int(10, 2)
test_format_int_hex := format_int(255, 16)

test_intersection := intersection({{1, 2, 3}, {2, 3, 4}})
test_union := union({{1, 2}, {2, 3}})

test_trace := trace("test message")
test_opa_runtime := opa.runtime()
test_object_union_n := object.union_n([{"a": 1}, {"b": 2}, {"a": 3}])
test_rand := rand.intn("seed", 100)

test_semver_is_valid := semver.is_valid("1.2.3")
test_semver_compare := semver.compare("1.2.3", "1.2.4")

test_glob_quote_meta := glob.quote_meta("*.txt")

test_regex_match := regex.match("h.*o", "hello")

test_net_cidr_contains := net.cidr_contains("192.168.1.0/24", "192.168.1.50")

test_uuid := uuid.rfc4122("test-seed")

test_units_parse := units.parse("10K")
test_units_parse_bytes := units.parse_bytes("1KB")

test_time_parse_duration := time.parse_duration_ns("1h30m")
test_time_date := time.date(1640000000000000000)
test_time_clock := time.clock(1640000000000000000)
test_time_weekday := time.weekday(1640000000000000000)

result := {
    "sprintf": test_sprintf,
    "concat": test_concat,
    "contains": test_contains,
    "startswith": test_startswith,
    "endswith": test_endswith,
    "indexof": test_indexof,
    "indexof_n": test_indexof_n,
    "lower": test_lower,
    "upper": test_upper,
    "split": test_split,
    "replace": test_replace,
    "substring": test_substring,
    "trim": test_trim,
    "trim_space": test_trim_space,
    "strings_reverse": test_strings_reverse,
    "abs": test_abs,
    "round": test_round,
    "ceil": test_ceil,
    "floor": test_floor,
    "sum": test_sum,
    "product": test_product,
    "max": test_max,
    "min": test_min,
    "numbers_range": test_numbers_range,
    "array_concat": test_array_concat,
    "array_slice": test_array_slice,
    "array_reverse": test_array_reverse,
    "sort": test_sort,
    "count_array": test_count_array,
    "count_string": test_count_string,
    "object_get": test_object_get,
    "object_get_default": test_object_get_default,
    "object_keys": test_object_keys,
    "type_name_string": test_type_name_string,
    "is_string": test_is_string,
    "is_number": test_is_number,
    "base64_encode": test_base64_encode,
    "base64_decode": test_base64_decode,
    "hex_encode": test_hex_encode,
    "hex_decode": test_hex_decode,
    "urlquery_encode": test_urlquery_encode,
    "urlquery_decode": test_urlquery_decode,
    "crypto_md5": test_crypto_md5,
    "crypto_sha256": test_crypto_sha256,
    "json_is_valid": test_json_is_valid,
    "json_marshal": test_json_marshal,
    "format_int_hex": test_format_int_hex,
    "intersection": test_intersection,
    "union": test_union,
    "trace": test_trace,
    "opa_runtime": test_opa_runtime,
    "object_union_n": test_object_union_n,
    "rand": test_rand,
    "semver_is_valid": test_semver_is_valid,
    "semver_compare": test_semver_compare,
    "glob_quote_meta": test_glob_quote_meta,
    "regex_match": test_regex_match,
    "net_cidr_contains": test_net_cidr_contains,
    "uuid": test_uuid,
    "units_parse": test_units_parse,
    "units_parse_bytes": test_units_parse_bytes,
    "time_parse_duration": test_time_parse_duration,
    "time_date": test_time_date,
    "time_clock": test_time_clock,
    "time_weekday": test_time_weekday,
}

default allow := false

allow if {
    test_contains
    test_is_string
    test_sum == 10
}
