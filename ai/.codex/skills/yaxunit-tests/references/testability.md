# YAxUnit Testability

Read this reference only after a concrete testability obstacle appears. Do not evaluate every mechanism preemptively. Stop at the first simple, deterministic seam that covers the material behavior and risk.

## Escalation order

```text
public production API
-> existing shared semantic fixture
-> suitable `ЮТест.Данные()` builder/generator
-> YAxUnit Mockito
-> unit test-extension seam
-> product seam/refactoring
-> unsupported
```

Do not claim `requires product refactoring`, `requires product seam`, `cannot unit test`, or `unsupported` before checking the applicable earlier options. If an option resolves the obstacle, do not keep researching alternatives without a material advantage.

## Choose the seam

- Use the public API when it exposes the behavior through a stable, reasonably small setup.
- Reuse an existing shared fixture only when it semantically represents the scenario data. Otherwise use the suitable public `ЮТест.Данные()` builder/generator before adding custom data infrastructure or escalating to a test seam. A fixture or builder solves setup, not inaccessible code or an uncontrollable dependency.
- Use Mockito when the obstacle is the behavior of an external inter-module dependency: return value, exception, skipped execution, observation, or another installed-core reaction. Typical boundaries are Kafka transport, HTTP, external common modules, generators, and costly or unstable services.
- Use a test-only alias when substantial private logic is inaccessible and the public path requires unrelated setup, external infrastructure, waiting/background execution, many edge cases, or gives poorly localized failures.
- Use an extension override when the test configuration must replace an implementation that Mockito cannot intercept in the required context, such as a platform call, extension method, wait, or environment/transport boundary.
- Use a test wrapper when a compact stable test entry point is needed without changing the production API.

Do not mock deterministic helpers, cheap data construction, or the business logic being tested. Verify interactions only when the interaction itself is required behavior.

## Mockito limits

The installed YAxUnit core is the exact API authority. Its documented model uses borrowed configuration methods and `&Вместо` interceptors, and can control private or exported configuration methods. It does not directly mock platform methods, methods implemented in extensions, or external reports/processors.

Confirm a new reaction, matcher, call-verification rule, client/server behavior, or interceptor shape once against the installed core. Reuse that contract for the rest of the session unless execution contradicts it. If Mockito is unsuitable, continue to the extension seam instead of building heavy infrastructure by default.

## `unit` as a white-box harness

In Kafka, `unit` may borrow an object from the base configuration and add test-only behavior without widening the production API. Before choosing a mechanism, inspect the live object and available extension operation through EDT; do not invent an annotation, signature, or supported object type.

For meaningful private logic, prefer a minimal exported alias in the borrowed object's `unit` module when the platform/EDT model permits it:

```bsl
Функция кфк_т_ВыполнитьРасчет(Параметры) Экспорт

    Возврат ВыполнитьРасчет(Параметры);

КонецФункции
```

The alias must exist only in the test extension, use an explicit test-only name such as `кфк_т_*`, contain no business logic, and only expose the original private method. Do not add aliases for trivial methods, implementation details with little risk, or behavior easily covered through a stable public contract.

For replacement seams, evaluate standard extension mechanisms supported by the live object, including borrowed methods with `&Вместо` and targeted `&ИзменениеИКонтроль` changes. Use them only in the test contour, keep the changed area minimal, and retain the maintenance obligation of the extended method. Verify annotations, signatures, call continuation, execution context, and extension compatibility through EDT/platform documentation before mutation.

## Product changes are last

Change or propose production code solely for testability only when the public route, fixtures, Mockito, test-only alias, extension override, and wrapper cannot provide a deterministic and maintainable test. State briefly why the applicable alternatives fail. Product scope still requires explicit authorization; test work does not grant it.
