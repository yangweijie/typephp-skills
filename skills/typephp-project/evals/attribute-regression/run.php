<?php
/**
 * Regression runner for the TypePHP attribute/type-annotation evidence set.
 *
 * Each fixture declares its expectation on line 2:
 *   // expect: FAIL | <substring that must appear in the compiler output>
 *   // expect: PASS                      (--dry must succeed)
 *   // expect: PASS_WARN | <substring>   (--dry succeeds AND prints the substring)
 *   // expect: RUN | <regex on stdout>   (build the binary, run it, match output)
 *
 *   php run.php <cases-dir> [--build]
 *
 * --build enables the RUN cases; they compile and link a real binary (~1-2 min each).
 * Without it, RUN cases are reported as SKIP.
 */

declare(strict_types=1);

$dir = $argv[1] ?? __DIR__ . '/cases';
$dir = str_replace('\\', '/', realpath($dir) ?: $dir);
$doBuild = in_array('--build', $argv, true);
$phpHome = getenv('PHP_HOME');
$tpc = $phpHome . '/tpc.exe';
$work = sys_get_temp_dir() . '/typephp-attr-regress';

if (!is_dir($work)) {
    mkdir($work, 0777, true);
}

function runTpc(string $tpc, string $file, string $buildDir, array $extra = []): string
{
    $cmd = array_merge([$tpc, '--dry', $file, '--no-progress', '--build-dir', $buildDir], $extra);
    $proc = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, dirname($file));
    $out = stream_get_contents($pipes[1]) . stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($proc);
    return $out;
}

$files = glob($dir . '/*.php');
sort($files);

$pass = 0;
$fail = 0;
$skip = 0;
$failures = [];

foreach ($files as $file) {
    $src = (string) file_get_contents($file);
    $name = basename($file);

    if (!preg_match('#^//\s*expect:\s*(\S+)(?:\s*[| ]\s*(.+?))?\s*$#m', $src, $m)) {
        echo "NOEXP $name\n";
        $skip++;
        continue;
    }
    $kind = strtoupper($m[1]);
    $want = isset($m[2]) ? trim($m[2]) : '';
    $buildDir = $work . '/bd-' . pathinfo($file, PATHINFO_FILENAME);

    if ($kind === 'RUN' || $kind === 'PASS_RUN') {
        if (!$doBuild) {
            printf("SKIP  %-38s (RUN case, needs --build)\n", $name);
            $skip++;
            continue;
        }
        $exe = $work . '/' . pathinfo($file, PATHINFO_FILENAME) . '.exe';
        $buildOut = shell_exec(sprintf('cmd /c "call "%s" >nul 2>&1 & "%s" "%s" -o "%s" --no-progress --build-dir "%s" 2>&1"',
            'D:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat',
            str_replace('/', '\\', $tpc), str_replace('/', '\\', $file),
            str_replace('/', '\\', $exe), str_replace('/', '\\', $buildDir)));
        if (!is_file($exe)) {
            printf("FAIL  %-38s build failed\n", $name);
            $fail++;
            $failures[] = "$name: build produced no exe\n" . substr((string) $buildOut, -400);
            continue;
        }
        $runOut = shell_exec('"' . str_replace('/', '\\', $exe) . '" 2>&1');
        $runOut = (string) $runOut;
        $ok = $want === '' ? true : (bool) preg_match('#' . $want . '#m', $runOut);
        printf("%s  %-38s %s\n", $ok ? 'ok  ' : 'FAIL', $name, $ok ? 'run matched' : 'run mismatch');
        if ($ok) {
            $pass++;
        } else {
            $fail++;
            $failures[] = "$name: expected /$want/ in output:\n$runOut";
        }
        continue;
    }

    $out = runTpc($tpc, $file, $buildDir);
    $isFatal = (bool) preg_match('/^Fatal error/m', $out);

    if ($kind === 'FAIL') {
        $ok = $isFatal && ($want === '' || str_contains($out, $want));
        printf("%s  %-38s %s\n", $ok ? 'ok  ' : 'FAIL', $name,
            $ok ? 'rejected as expected' : ($isFatal ? 'wrong message' : 'compiled but should fail'));
    } elseif ($kind === 'PASS') {
        $ok = !$isFatal;
        printf("%s  %-38s %s\n", $ok ? 'ok  ' : 'FAIL', $name, $ok ? 'compiled' : 'should compile');
    } elseif ($kind === 'PASS_WARN') {
        $ok = !$isFatal && ($want === '' || str_contains($out, $want));
        printf("%s  %-38s %s\n", $ok ? 'ok  ' : 'FAIL', $name,
            $ok ? 'compiled with expected warning' : 'missing expected warning');
    } else {
        printf("SKIP  %-38s unknown expectation %s\n", $name, $kind);
        $skip++;
        continue;
    }

    if ($ok) {
        $pass++;
    } else {
        $fail++;
        $failures[] = "$name:\n" . substr($out, 0, 500);
    }
}

echo "\n", str_repeat('-', 60), "\n";
printf("pass=%d fail=%d skip=%d\n", $pass, $fail, $skip);
foreach ($failures as $f) {
    echo "\n=== $f\n";
}
exit($fail === 0 ? 0 : 1);
