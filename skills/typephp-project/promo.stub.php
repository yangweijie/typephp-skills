<?php

/** @import-library */

namespace {
    /**
     * 内置优惠规则。规则保持稳定，只把可变参数（等级、券码、运费）交给宿主传入。
     */
    function promo_rules(): array
    {
    }
    /**
     * 计算购物车优惠与应付金额。
     *
     * @param array $cart    [['price' => float, 'qty' => int, 'tag' => 'digital'|'physical'], ...]
     * @param array $context ['level' => string, 'coupon' => string|null, 'shipping' => float]
     */
    function promo_quote(array $cart, array $context = []): array
    {
    }
}
