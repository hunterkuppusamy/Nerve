# About
A language hosted in [Zig](https://ziglang.org/) that compiles to [JVM bytecode](https://docs.oracle.com/javase/specs/jvms/se8/html/). 

# Syntax
```
const var String = [import]("java/lang/String")
const var System = [import]("java/lang/String")
const var Main = type {
  const var number = 1 + 2
  static pub const var main = fn (args: []String) -> void {
    const var str = "Hello, World!";
    System.out.println(str);
    return;
  }
}
```

# Objectives
  Discover the limits of the JVM with regards to memory (without forking a JVM implementation), 
  keep declarations value based, ensure interoperability with Nerve and any bytecode compiled language, and of course to learn.

# CLI
Run the Nerve binary with arguments to compile
> CLI is not yet complete, so this section is a stub.

# Use
If there is a release for your operating system, you may download that binary and use it. You need to specify a directory 
containing an extracted JDK for now, but the hope is to eventually parse the java.base module in a JDK directly.

You can build the binary for your operating system by running `zig build install` in the root directory of the project. 
You need to have zig installed for this command, as well as the correct version (although if it is the wrong version zig will tell you how to fix it).
