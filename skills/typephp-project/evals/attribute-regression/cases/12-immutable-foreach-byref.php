<?php
// expect: PASS
// Regression guard: foreach-by-ref over a COPY from an Immutable method is allowed.
// (What IS rejected: foreach-by-ref over the object's own property — see performance notes.)
use \Immutable;

class U
{
    private array $items = [1, 2, 3];

    #[Immutable]
    public function items(): array
    {
        return $this->items;
    }
}

function g(#[Immutable] U $u): void
{
    $copy = $u->items();
    foreach ($copy as &$v) {
        $v = $v * 2;
    }
}

function main(): void
{
    $u = new U();
    g($u);
    echo "done\n";
}
