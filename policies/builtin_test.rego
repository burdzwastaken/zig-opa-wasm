package builtin_test

import rego.v1

test_sprintf := sprintf("Hello, %s! You have %d messages.", [input.name, input.count])
test_concat := concat(", ", ["a", "b", "c"])
test_indexof := indexof("hello", "l")
test_indexof_n := indexof_n("hello", "l")
test_contains := contains("hello world", "world")
test_startswith := startswith("hello world", "hello")
test_endswith := endswith("hello world", "world")
test_lower := lower("HELLO")
test_upper := upper("hello")
test_trim := trim("  hello  ", " ")
test_trim_left := trim_left("  hello", " ")
test_trim_right := trim_right("hello  ", " ")
test_trim_prefix := trim_prefix("hello world", "hello ")
test_trim_suffix := trim_suffix("hello world", " world")
test_trim_space := trim_space("  hello  ")
test_replace := replace("hello", "l", "L")
test_split := split("a,b,c", ",")
test_substring := substring("hello", 1, 3)
test_strings_reverse := strings.reverse("hello")
test_strings_replace_n := strings.replace_n({"l": "L", "o": "0"}, "hello")
test_strings_any_prefix_match := strings.any_prefix_match("hello", ["he", "wo"])
test_strings_any_suffix_match := strings.any_suffix_match("hello", ["lo", "ld"])
test_strings_count := strings.count("hello", "l")

test_abs := abs(-5)
test_round := round(3.7)
test_ceil := ceil(3.2)
test_floor := floor(3.8)
test_numbers_range := numbers.range(1, 5)
test_numbers_range_step := numbers.range_step(0, 10, 2)
test_sum := sum([1, 2, 3, 4])
test_product := product([2, 3, 4])
test_max := max([1, 5, 3])
test_min := min([1, 5, 3])
test_format_int_binary := format_int(10, 2)
test_format_int_hex := format_int(255, 16)

test_array_concat := array.concat([1, 2], [3, 4])
test_array_slice := array.slice([1, 2, 3, 4, 5], 1, 3)
test_array_reverse := array.reverse([1, 2, 3])
test_sort := sort([3, 1, 2])
test_count_array := count([1, 2, 3])
test_count_string := count("hello")
test_count_object := count({"a": 1, "b": 2})
test_intersection := intersection({{1, 2, 3}, {2, 3, 4}})
test_union := union({{1, 2}, {2, 3}})

test_object_get := object.get({"a": 1}, "a", 0)
test_object_get_default := object.get({"a": 1}, "b", 99)
test_object_keys := object.keys({"a": 1, "b": 2})
test_object_remove := object.remove({"a": 1, "b": 2}, ["a"])
test_object_union_n := object.union_n([{"a": 1}, {"b": 2}, {"a": 3}])
test_object_filter := object.filter({"a": 1, "b": 2, "c": 3}, ["a", "c"])
test_object_subset := object.subset({"a": 1, "b": 2}, {"a": 1})

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
test_is_set := is_set({1, 2, 3})
test_to_number := to_number("42")

test_base64_encode := base64.encode("hello")
test_base64_decode := base64.decode("aGVsbG8=")
test_base64_is_valid := base64.is_valid("aGVsbG8=")
test_base64url_encode := base64url.encode("hello")
test_base64url_encode_no_pad := base64url.encode_no_pad("hello")
test_base64url_decode := base64url.decode("aGVsbG8")
test_hex_encode := hex.encode("hello")
test_hex_decode := hex.decode("68656c6c6f")
test_urlquery_encode := urlquery.encode("hello world")
test_urlquery_decode := urlquery.decode("hello%20world")
test_urlquery_encode_object := urlquery.encode_object({"a": "1", "b": "2"})
test_urlquery_decode_object := urlquery.decode_object("a=1&b=2")

test_crypto_md5 := crypto.md5("hello")
test_crypto_sha1 := crypto.sha1("hello")
test_crypto_sha256 := crypto.sha256("hello")

test_json_is_valid := json.is_valid("{\"a\": 1}")
test_json_marshal := json.marshal({"a": 1})
test_json_unmarshal := json.unmarshal("{\"a\": 1}")
test_json_filter := json.filter({"a": {"b": 1, "c": 2}}, ["a/b"])
test_json_remove := json.remove({"a": 1, "b": 2}, ["a"])
test_json_patch := json.patch({"a": 1}, [{"op": "add", "path": "/b", "value": 2}])

test_time_now_ns := time.now_ns()
test_trace := trace("test message")
test_opa_runtime := opa.runtime()
test_rand := rand.intn("seed", 100)

test_regex_match := regex.match("h.*o", "hello")
test_regex_find_n := regex.find_n("l", "hello", 2)
test_regex_split := regex.split(",", "a,b,c")
test_regex_replace := regex.replace("hello", "l", "L")
test_regex_is_valid := regex.is_valid("h.*o")
test_regex_globs_match := regex.globs_match("*.txt", "*.txt")

test_net_cidr_contains := net.cidr_contains("192.168.1.0/24", "192.168.1.50")
test_net_cidr_intersects := net.cidr_intersects("192.168.1.0/24", "192.168.0.0/16")
test_net_cidr_is_valid := net.cidr_is_valid("192.168.1.0/24")

test_semver_compare := semver.compare("1.2.3", "1.2.4")
test_semver_is_valid := semver.is_valid("1.2.3")

test_glob_quote_meta := glob.quote_meta("*.txt")
test_glob_match := glob.match("*.txt", ["."], "hello.txt")

test_time_parse_ns := time.parse_ns("2006-01-02", "2023-06-15")
test_time_parse_rfc3339_ns := time.parse_rfc3339_ns("2023-06-15T10:30:00Z")
test_time_parse_duration := time.parse_duration_ns("1h30m")
test_time_date := time.date(1640000000000000000)
test_time_clock := time.clock(1640000000000000000)
test_time_weekday := time.weekday(1640000000000000000)
test_time_add_date := time.add_date(1640000000000000000, 1, 0, 0)
test_time_diff := time.diff(1640000000000000000, 1650000000000000000)
test_time_format := time.format(1640000000000000000)

test_yaml_is_valid := yaml.is_valid("a: 1")
test_yaml_marshal := yaml.marshal({"a": 1})
test_yaml_unmarshal := yaml.unmarshal("a: 1")

test_uuid := uuid.rfc4122("test-seed")
test_uuid_parse := uuid.parse("550e8400-e29b-41d4-a716-446655440000")

test_units_parse := units.parse("10K")
test_units_parse_bytes := units.parse_bytes("1KB")

test_bits_or := bits.or(5, 3)
test_bits_and := bits.and(5, 3)
test_bits_negate := bits.negate(5)
test_bits_xor := bits.xor(5, 3)
test_bits_lsh := bits.lsh(1, 4)
test_bits_rsh := bits.rsh(16, 2)

test_graph_reachable := graph.reachable({"a": ["b"], "b": ["c"]}, ["a"])
test_graph_reachable_paths := graph.reachable_paths({"a": ["b"], "b": ["c"]}, ["a"])

result := {
	"sprintf": test_sprintf,
	"concat": test_concat,
	"indexof": test_indexof,
	"indexof_n": test_indexof_n,
	"contains": test_contains,
	"startswith": test_startswith,
	"endswith": test_endswith,
	"lower": test_lower,
	"upper": test_upper,
	"trim": test_trim,
	"trim_left": test_trim_left,
	"trim_right": test_trim_right,
	"trim_prefix": test_trim_prefix,
	"trim_suffix": test_trim_suffix,
	"trim_space": test_trim_space,
	"replace": test_replace,
	"split": test_split,
	"substring": test_substring,
	"strings_reverse": test_strings_reverse,
	"strings_replace_n": test_strings_replace_n,
	"strings_any_prefix_match": test_strings_any_prefix_match,
	"strings_any_suffix_match": test_strings_any_suffix_match,
	"strings_count": test_strings_count,
	"abs": test_abs,
	"round": test_round,
	"ceil": test_ceil,
	"floor": test_floor,
	"numbers_range": test_numbers_range,
	"numbers_range_step": test_numbers_range_step,
	"sum": test_sum,
	"product": test_product,
	"max": test_max,
	"min": test_min,
	"format_int_binary": test_format_int_binary,
	"format_int_hex": test_format_int_hex,
	"array_concat": test_array_concat,
	"array_slice": test_array_slice,
	"array_reverse": test_array_reverse,
	"sort": test_sort,
	"count_array": test_count_array,
	"count_string": test_count_string,
	"count_object": test_count_object,
	"intersection": test_intersection,
	"union": test_union,
	"object_get": test_object_get,
	"object_get_default": test_object_get_default,
	"object_keys": test_object_keys,
	"object_remove": test_object_remove,
	"object_union_n": test_object_union_n,
	"object_filter": test_object_filter,
	"object_subset": test_object_subset,
	"type_name_string": test_type_name_string,
	"type_name_number": test_type_name_number,
	"type_name_array": test_type_name_array,
	"type_name_object": test_type_name_object,
	"is_string": test_is_string,
	"is_number": test_is_number,
	"is_boolean": test_is_boolean,
	"is_array": test_is_array,
	"is_object": test_is_object,
	"is_null": test_is_null,
	"is_set": test_is_set,
	"to_number": test_to_number,
	"base64_encode": test_base64_encode,
	"base64_decode": test_base64_decode,
	"base64_is_valid": test_base64_is_valid,
	"base64url_encode": test_base64url_encode,
	"base64url_encode_no_pad": test_base64url_encode_no_pad,
	"base64url_decode": test_base64url_decode,
	"hex_encode": test_hex_encode,
	"hex_decode": test_hex_decode,
	"urlquery_encode": test_urlquery_encode,
	"urlquery_decode": test_urlquery_decode,
	"urlquery_encode_object": test_urlquery_encode_object,
	"urlquery_decode_object": test_urlquery_decode_object,
	"crypto_md5": test_crypto_md5,
	"crypto_sha1": test_crypto_sha1,
	"crypto_sha256": test_crypto_sha256,
	"json_is_valid": test_json_is_valid,
	"json_marshal": test_json_marshal,
	"json_unmarshal": test_json_unmarshal,
	"json_filter": test_json_filter,
	"json_remove": test_json_remove,
	"json_patch": test_json_patch,
	"time_now_ns": test_time_now_ns,
	"trace": test_trace,
	"opa_runtime": test_opa_runtime,
	"rand": test_rand,
	"regex_match": test_regex_match,
	"regex_find_n": test_regex_find_n,
	"regex_split": test_regex_split,
	"regex_replace": test_regex_replace,
	"regex_is_valid": test_regex_is_valid,
	"regex_globs_match": test_regex_globs_match,
	"net_cidr_contains": test_net_cidr_contains,
	"net_cidr_intersects": test_net_cidr_intersects,
	"net_cidr_is_valid": test_net_cidr_is_valid,
	"semver_compare": test_semver_compare,
	"semver_is_valid": test_semver_is_valid,
	"glob_quote_meta": test_glob_quote_meta,
	"glob_match": test_glob_match,
	"time_parse_ns": test_time_parse_ns,
	"time_parse_rfc3339_ns": test_time_parse_rfc3339_ns,
	"time_parse_duration": test_time_parse_duration,
	"time_date": test_time_date,
	"time_clock": test_time_clock,
	"time_weekday": test_time_weekday,
	"time_add_date": test_time_add_date,
	"time_diff": test_time_diff,
	"time_format": test_time_format,
	"yaml_is_valid": test_yaml_is_valid,
	"yaml_marshal": test_yaml_marshal,
	"yaml_unmarshal": test_yaml_unmarshal,
	"uuid": test_uuid,
	"uuid_parse": test_uuid_parse,
	"units_parse": test_units_parse,
	"units_parse_bytes": test_units_parse_bytes,
	"bits_or": test_bits_or,
	"bits_and": test_bits_and,
	"bits_negate": test_bits_negate,
	"bits_xor": test_bits_xor,
	"bits_lsh": test_bits_lsh,
	"bits_rsh": test_bits_rsh,
	"graph_reachable": test_graph_reachable,
	"graph_reachable_paths": test_graph_reachable_paths,
}

default allow := false

allow if {
	test_contains
	test_is_string
	test_sum == 10
}
