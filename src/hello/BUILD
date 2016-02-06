package(default_visibility = ["//visibility:public"])

load("//tools/build_rules/go:def.bzl", "go_binary", "go_library", "go_test")

go_binary(
  name = "hello_go",
  srcs = ["hello.go"],
)

java_binary(
  name = "hello_java",
  srcs = ["Hello.java"],
  main_class = "hello.Hello",
)

cc_binary(
  name = "hello_c",
  srcs = ["hello.c"],
)

cc_binary(
  name = "hello_cpp",
  srcs = ["hello.cpp"],
)

py_binary(
  name = "hello_py",
  srcs = ["hello.py"],
  main = "hello.py",
)
