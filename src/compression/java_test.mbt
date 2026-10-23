///|
test "Java complete signatures, conservative fields, nested and anonymous type APIs" {
  let source =
    #|package example.api;
    #|import java.io.IOException;
    #|import java.util.*;
    #|import static java.util.Collections.emptyList;
    #|/** API 文档 😀 */
    #|@Deprecated
    #|public abstract class Api<T extends Number & Comparable<T>> extends Base<T> implements AutoCloseable, Iterable<T> {
    #|  public static final Map<String, List<Integer>> SCHEMA = Map.of("items", List.of(1, 2, 3));
    #|  protected final int[] dimensions = {1, 2, 3};
    #|  public String literal = "class Fake { void hidden() {} } // not a comment";
    #|  public <U extends T> Api(@Deprecated U initial) throws IOException { super(initial); initializeImplementation(initial); }
    #|  @Deprecated
    #|  protected abstract <R extends T> List<? super R[]> read(final R... values) throws IOException, IllegalStateException;
    #|  public native synchronized long nativeCall(byte[] bytes) throws IOException;
    #|  public <R extends Comparable<? super R>> Map<String, ? extends R[]>[] convert(@Deprecated final R... values) throws IOException {
    #|    // caller retains ownership
    #|    if (values.length > 0) { for (R value : values) { implementationLoop(value); } }
    #|    try { throw new IOException("implementation failure"); } finally { implementationCleanup(); }
    #|  }
    #|  protected interface Reader<E> extends Iterable<E> {
    #|    E read() throws IOException;
    #|    default E first() throws IOException { return implementationDefault(); }
    #|  }
    #|  public enum Mode implements Runnable {
    #|    FAST(1) { @Override public void run() { implementationEnum(); } }, SLOW(2);
    #|    public final int code;
    #|    { implementationEnumInit(); }
    #|    Mode(int code) { this.code = code; implementationConstructor(); }
    #|    public void run() { implementationRun(); }
    #|  }
    #|  public record Pair<K, V>(@Deprecated K key, V value) implements java.io.Serializable {
    #|    public Pair { if (key == null) throw new IllegalArgumentException("implementation record"); }
    #|    public Pair(K key) { this(key, null); implementationRecordCtor(); }
    #|    public V value() { return implementationValue(); }
    #|  }
    #|  public @interface Schema { String[] names() default {"one", "two"}; Class<?> type() default String.class; }
    #|  public sealed interface Action permits Done {}
    #|  public record Done(int code) implements Action {}
    #|  protected static class Nested<X> { public X get() throws IOException { return implementationNested(); } }
    #|  public final Runnable task = new Runnable() { @Override public void run() { implementationAnonymous(); } };
    #|  public final java.util.function.Function<String, String> mapper = value -> value.strip().repeat(100);
    #|  static { implementationStatic(); class InitLocal { public void start() { implementationInitLocal(); } } }
    #|  { implementationInstance(); }
    #|  public Object factory() {
    #|    if (implementationCondition()) {
    #|      class Local { public String name() { return "implementation local"; } }
    #|    }
    #|    return new Runnable() { @Override public void run() { implementationReturned(); } };
    #|  }
    #|}
    #|
  let out = @compression.compress("Api.JAVA", source)
  assert_eq(out.language, Some("java"))
  assert_eq(out.reason, None)
  assert_true(out.applied)
  for
    anchor in [
      "package example.api;", "import java.io.IOException;", "import java.util.*;",
      "import static java.util.Collections.emptyList;", "/** API 文档 😀 */",
      "@Deprecated", "public abstract class Api<T extends Number & Comparable<T>> extends Base<T> implements AutoCloseable, Iterable<T>",
      "public static final Map<String, List<Integer>> SCHEMA = Map.of(\"items\", List.of(1, 2, 3));",
      "protected final int[] dimensions = {1, 2, 3};", "public String literal = \"class Fake { void hidden() {} } // not a comment\";",
      "public <U extends T> Api(@Deprecated U initial) throws IOException", "protected abstract <R extends T> List<? super R[]> read(final R... values) throws IOException, IllegalStateException;",
      "public native synchronized long nativeCall(byte[] bytes) throws IOException;",
      "public <R extends Comparable<? super R>> Map<String, ? extends R[]>[] convert(@Deprecated final R... values) throws IOException",
      "// caller retains ownership", "protected interface Reader<E> extends Iterable<E>",
      "E read() throws IOException;", "default E first() throws IOException", "public enum Mode implements Runnable",
      "FAST(1)", "SLOW(2)", "public final int code;", "Mode(int code)", "@Override public void run()",
      "public record Pair<K, V>(@Deprecated K key, V value) implements java.io.Serializable",
      "public Pair {", "public Pair(K key)", "public V value()", "public @interface Schema",
      "String[] names() default {\"one\", \"two\"};", "Class<?> type() default String.class;",
      "public sealed interface Action permits Done {}", "public record Done(int code) implements Action {}",
      "protected static class Nested<X>", "public X get() throws IOException", "public final Runnable task = new Runnable()",
      "public final java.util.function.Function<String, String> mapper = value ->",
      "class InitLocal", "public void start()", "public Object factory()", "class Local",
      "public String name()", "new Runnable()",
    ] {
    assert_true(out.text.contains(anchor), msg=anchor)
  }
  for
    detail in [
      "initializeImplementation", "implementation", "super(initial)", "this(key, null)",
      "this.code = code", "value.strip().repeat(100)", "if (", "for (", "try {",
      "finally",
    ] {
    assert_false(out.text.contains(detail), msg=detail)
  }
  // Both anonymous bodies are outlined, not merely the field's first one.
  assert_eq(out.text.split("@Override public void run()").collect().length(), 4)
}

///|
test "Java original reference anchors, exact CRLF ranges and lossless fallbacks" {
  // Independent HelloWorld input and all API anchors from unmodified repomix
  // 1.18.1 parseFile.java.test.ts. Do not emulate its truncation behavior.
  let reference =
    #|
    #|      /**
    #|       * A simple Hello World class
    #|       */
    #|      public class HelloWorld {
    #|        /**
    #|         * Main entry point
    #|         * @param args command line arguments
    #|         */
    #|        public static void main(String[] args) {
    #|          System.out.println("Hello, world!");
    #|        }
    #|      }
    #|
  // The original JS template literal ends with four indentation spaces.
  let reference = reference + "    "
  assert_eq(reference.length(), 305)
  let out = @compression.compress("dummy.java", reference)
  assert_true(out.applied)
  for
    anchor in [
      "/**", "* A simple Hello World class", "*/", "public class HelloWorld {", "* Main entry point",
      "* @param args command line arguments", "public static void main(String[] args) {",
    ] {
    assert_true(out.text.contains(anchor), msg=anchor)
  }
  assert_false(out.text.contains("System.out.println"))
  let source = "/** 文档 😀 */\r\nclass Api {\r\n  public String get() throws Exception {\r\n    return \"long implementation\";\r\n  }\r\n}\r\n"
  let exact = @compression.compress("Api.java", source)
  assert_true(exact.applied)
  assert_eq(
    exact.text,
    "/** 文档 😀 */\r\nclass Api {\r\n  public String get() throws Exception {\r\n    /* … */\r\n  }\r\n}\r\n",
  )
  assert_eq(exact.ranges, [
    { start_line: 1, end_line: 3, },
    { start_line: 5, end_line: 6, },
  ])
  for
    source in [
      "", "package api;\nimport java.util.List;\npublic interface Read<T> { T read() throws Exception; }\n",
      "public record Pair<K, V>(K key, V value) {}\n", "class Api { public native int call(); public static final int[] DATA = {1, 2, 3}; }\n",
      "@interface Schema { String[] value() default {\"a\", \"b\"}; }\n", "class Short { void run() {} }\n",
      "module example.api { requires java.base; exports example.api; }\n",
    ] {
    let fallback = @compression.compress("Api.java", source)
    assert_eq(fallback.language, Some("java"))
    assert_false(fallback.applied)
    assert_eq(fallback.reason, Some("not-smaller"))
    assert_eq(fallback.text, source)
    assert_eq(fallback.ranges, [])
  }
  for
    source in [
      "class Broken { public void run( {", "class Missing { void run() { return; }",
    ] {
    let fallback = @compression.compress("Bad.java", source)
    assert_eq(fallback.language, Some("java"))
    assert_eq(fallback.reason, Some("parse-error"))
    assert_false(fallback.applied)
    assert_eq(fallback.text, source)
    assert_eq(fallback.ranges, [])
  }
  let unsupported = @compression.compress("Api.java.txt", source)
  assert_eq(unsupported.language, None)
  assert_eq(unsupported.reason, Some("unsupported"))
  assert_eq(unsupported.text, source)
  assert_false(unsupported.applied)
  assert_eq(unsupported.ranges, [])
}
