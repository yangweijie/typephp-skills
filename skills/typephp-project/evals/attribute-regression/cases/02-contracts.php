<?php

// expect: PASS_RUN
// NotNull / NotEmpty / Validate: behaviour, ValueError text, ordering, 0 handling.

use \NotNull;
use \NotEmpty;
use \Validate;

function requiredName(#[NotEmpty] string $name): string
{
    return 'ok:' . $name;
}

function requiredId(#[NotNull] ?int $id): int
{
    return $id ?? -1;
}

function checked(
    #[Validate(FILTER_VALIDATE_EMAIL)]
    #[NotEmpty]
    #[NotNull]
    string $email,
): string {
    return 'mail:' . $email;
}

function main(): void
{
    foreach (['', '0'] as $v) {
        try {
            requiredName($v);
            echo "NotEmpty('", $v, "'): NO THROW\n";
        } catch (\ValueError $e) {
            echo "NotEmpty('", $v, "'): ", $e->getMessage(), "\n";
        }
    }
    echo requiredName('rango'), "\n";

    try {
        requiredId(null);
        echo "NotNull(null): NO THROW\n";
    } catch (\ValueError $e) {
        echo "NotNull(null): ", $e->getMessage(), "\n";
    }
    echo 'NotNull(0) -> ', requiredId(0), "\n";

    try {
        checked('not-an-email');
        echo "Validate(bad): NO THROW\n";
    } catch (\ValueError $e) {
        echo "Validate(bad): ", $e->getMessage(), "\n";
    }
    echo checked('a@b.com'), "\n";
}
