# Lesson 2: The .NET toolchain

*Completed October 2, 2026.*

**Goal:** understand the tools before leaning on them: what the SDK, the `dotnet` CLI, a `.csproj`, and NuGet each do. The first two real files go into the repo by hand: `global.json` and `.gitignore`.

**C# in this lesson:** a first taste, enough to see how compiling changes things compared to Python and JavaScript.

## The map: .NET in terms you know

| .NET | Python | JavaScript |
|---|---|---|
| **SDK** (compiler, CLI, templates) | Python + pip + build tools | Node + npm |
| **Runtime** (runs compiled code) | The Python interpreter | Node itself |
| `dotnet` CLI | `python` / `pip` | `node` / `npm` |
| `.csproj` | `pyproject.toml` | `package.json` |
| NuGet | PyPI / pip | npm registry |
| `global.json` | `.python-version` | `.nvmrc` |
| `bin/` and `obj/` | `__pycache__/`, `dist/` | `dist/`, build output |

The biggest difference: **C# is compiled.** `dotnet run` first turns the code into a `.dll` file, then runs it. Many mistakes are caught at that compile step, before the program starts.

## Exercise 1: What's installed?

```powershell
dotnet --version
dotnet --list-sdks
dotnet --list-runtimes
```

Note the SDK version for Exercise 5. The runtimes list has two kinds: `Microsoft.NETCore.App` (the base runtime) and `Microsoft.AspNetCore.App` (the web framework). A server only needs the **runtime**. The SDK is for building.

## Exercise 2: A throwaway console app

Work **outside** the repo. This is a scratch project.

```powershell
mkdir C:\dev\scratch
cd C:\dev\scratch
dotnet new console -n Hello
cd Hello
code .
```

`Hello.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
```

- **`Sdk="Microsoft.NET.Sdk"`**: which kind of project this is. An API uses `Microsoft.NET.Sdk.Web`.
- **`OutputType Exe`**: produce a runnable program rather than a library.
- **`TargetFramework net10.0`**: which version of .NET this code runs on.
- **`ImplicitUsings`**: auto-imports common namespaces.
- **`Nullable`**: turns on null-safety warnings.

There's no list of source files. Every `.cs` file in the folder is included automatically.

```powershell
dotnet run
```

Then look at `bin\Debug\net10.0\`. `Hello.dll` is the compiled program. `obj\` holds intermediate build files.

## Exercise 3: First C#, and breaking it

Replace everything in `Program.cs` with:

```csharp
var boats = new List<string> { "Wet Noodle", "Second Wind", "Knot Today" };

foreach (var boat in boats)
{
    Console.WriteLine($"{boat} is ready to sail");
}

Console.WriteLine($"Fleet size: {boats.Count}");
```

| C# | Python |
|---|---|
| `var boats = new List<string> {...};` | `boats = [...]` |
| `foreach (var boat in boats)` | `for boat in boats:` |
| `$"{boat} is ready"` | `f"{boat} is ready"` |
| `{ }` braces and `;` | indentation and line breaks |

`var` doesn't mean "any type." The compiler figures out the type (`List<string>`) and **locks it in**. Add `boats.Add(42);` and run: it's an error, because 42 isn't a string.

**Break it:** remove a semicolon and run again. The error has a code (`CS1002`), a file, a line, and a column, and nothing runs. Put the semicolon back.

## Exercise 4: A NuGet package

```powershell
dotnet add package Humanizer
```

`Hello.csproj` gains a `<PackageReference>` line, as `npm install` adds a line to `package.json`. Use it:

```csharp
using Humanizer;

var departed = DateTime.UtcNow.AddMinutes(-95);
Console.WriteLine($"Departed {departed.Humanize()}");
```

Convention puts `using` lines at the top of the file. The package itself is **not** in the project folder:

```powershell
ls $env:USERPROFILE\.nuget\packages\humanizer*
```

NuGet keeps one shared cache per machine, and projects reference it.

## Exercise 5: Pin the SDK in the repo

```powershell
cd C:\dev\drunkensailorapi\DrunkenSailorAPI
dotnet new globaljson --sdk-version <your SDK version from Exercise 1> --roll-forward latestFeature
```

**`rollForward: latestFeature`** means "this version or any newer patch or feature release of .NET 10, but never .NET 11."

**Break it:** change the version to `9.0.100`, run `dotnet --version` inside the repo, read the error, then put the version back.

## Exercise 6: Ignore build output

```powershell
dotnet new gitignore
```

In `.gitignore`, find `[Bb]in/` and `[Oo]bj/`. Those two lines matter most. `git status` should show only `global.json` and `.gitignore` as new files.

---

## Deliverable

Notes in `docs/lesson-02.txt`:

1. What's the difference between the SDK and the runtime? Which one would a production server need?
2. Where did Humanizer get downloaded, and how is that different from `node_modules`?
3. When you removed the semicolon, when did you find out compared to how Python would have behaved? Why might that matter for an API?
4. What error did `global.json` give you with `9.0.100`? What would `"rollForward": "disable"` do?
5. Why should `bin/` and `obj/` never be committed?

README: add a sentence to section 10 saying `global.json` pins the SDK.

```powershell
git add global.json .gitignore README.md docs/lesson-02.txt
git commit -m "Lesson 2: pin SDK and ignore build output"
```

## Takeaways from the review

- **A production server needs the ASP.NET Core runtime** (`Microsoft.AspNetCore.App`), not the SDK. Docker builds use a large `sdk` image to compile and a small `aspnet` image to run.
- **Only the `<PackageReference>` line is committed.** `dotnet restore` (run automatically by `build` and `run`) downloads packages on a fresh machine.
- **Correction to the original lesson:** Python also catches *syntax* errors before running anything. The real difference is **type and name errors**. Python finds those only when the exact line runs, so a typo in a rarely used branch can hide for months. C# refuses to build.
- **A successful build proves the code is consistent, not that it's correct.** Wrong logic, missing data, and an unreachable weather API still happen at runtime. Tests cover that gap.
- **`"rollForward": "disable"`** demands the exact version, including the patch number.
- **`bin/` and `obj/`** are generated, machine-specific, large, and reproducible from source. Security is a minor factor: the real rule is never to put secrets in config files at all.
- **Error code prefixes:** `CS` comes from the C# compiler, `MSB` from the build system (usually a broken project or solution file).
