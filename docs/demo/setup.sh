#!/usr/bin/env bash
# Create the workspace used by the demo recordings (docs/demo/*.tape).
#
#   docs/demo/setup.sh [dir]     default: /tmp/vim-project-demo
#
# Everything is recreated from scratch, so each recording starts the same.
set -euo pipefail

demo="${1:-/tmp/vim-project-demo}"
rm -rf "$demo"
mkdir -p "$demo/projects" "$demo/config"

now=$(date +%s)
commit() { # commit <days ago> <author> <message>
  local when=$(( now - $1 * 86400 ))
  GIT_AUTHOR_DATE="$when +0000" GIT_COMMITTER_DATE="$when +0000" \
    git -c user.name="$2" -c user.email="$(echo "$2" | tr 'A-Z ' 'a-z.')@example.com" \
    commit -q -m "$3"
}

# ---------------------------------------------------------------- webshop
shop="$demo/projects/webshop"
mkdir -p "$shop"/{src/{api,components,store,utils},tests,scripts}
cd "$shop"
git init -q -b main

cat > README.md <<'EOF'
# webshop

A small online shop: **product list**, cart and checkout.

## Getting started

```sh
npm install
npm run dev     # http://localhost:5173
```

## Features

- Browse products from `/api/products`
- Add items to the *cart*
- [Checkout](docs/checkout.md) with discounts

> Prices are stored in cents, see `src/utils/currency.js`.
EOF
cat > package.json <<'EOF'
{
  "name": "webshop",
  "scripts": { "dev": "vite", "test": "vitest run" }
}
EOF
cat > src/main.js <<'EOF'
import { createApp } from 'vue'
import { router } from './router'
import App from './App.vue'

createApp(App).use(router).mount('#app')
EOF
cat > src/router.js <<'EOF'
import { createRouter, createWebHistory } from 'vue-router'
import ProductList from './components/ProductList.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [{ path: '/', component: ProductList }],
})
EOF
cat > src/api/client.js <<'EOF'
export async function fetchProducts() {
  const response = await fetch('/api/products')
  return response.json()
}
EOF
git add -A && commit 30 "Ada Lovelace" "Set up the project"

cat > src/store/cart.js <<'EOF'
const items = []

export function addToCart(product) {
  items.push(product)
}

export function cartTotal() {
  return items.reduce((sum, item) => sum + item.price, 0)
}
EOF
cat > src/components/ProductCard.vue <<'EOF'
<script setup>
import { addToCart } from '../store/cart'
defineProps({ product: Object })
</script>

<template>
  <article class="card">
    <h2>{{ product.name }}</h2>
    <button @click="addToCart(product)">Add to cart</button>
  </article>
</template>
EOF
cat > src/components/ProductList.vue <<'EOF'
<script setup>
import { ref, onMounted } from 'vue'
import { fetchProducts } from '../api/client'
import ProductCard from './ProductCard.vue'

const products = ref([])
onMounted(async () => { products.value = await fetchProducts() })
</script>

<template>
  <ProductCard v-for="product in products" :key="product.id" :product="product" />
</template>
EOF
git add -A && commit 21 "Grace Hopper" "Add product list and cart"

cat > src/components/CartButton.vue <<'EOF'
<script setup>
import { addToCart, cartTotal } from '../store/cart'
defineProps({ product: Object })
</script>

<template>
  <button @click="addToCart(product)">Add · {{ cartTotal() }}</button>
</template>
EOF
cat > tests/cart.test.js <<'EOF'
import { addToCart, cartTotal } from '../src/store/cart'

test('adds up the cart', () => {
  addToCart({ price: 2 })
  addToCart({ price: 3 })
  expect(cartTotal()).toBe(5)
})
EOF
git add -A && commit 9 "Ada Lovelace" "Add cart button and tests"

cat > src/utils/currency.js <<'EOF'
export function formatPrice(cents) {
  return `$${(cents / 100).toFixed(2)}`
}
EOF
git add -A && commit 4 "Linus Torvalds" "Format prices as currency"
sed -i.bak 's/fetch(.\/api\/products.)/fetch("\/api\/products?limit=50")/' src/api/client.js && rm src/api/client.js.bak
git add -A && commit 1 "Grace Hopper" "Limit the products fetched"

# Scripts run by the demo tasks
cat > scripts/test.sh <<'EOF'
#!/bin/sh
echo " RUN  v1.6.0 webshop"
sleep 0.4; echo " ✓ tests/cart.test.js (1)"
sleep 0.4; echo " ✓ tests/product.test.js (3)"
sleep 0.3; echo ""
echo " Test Files  2 passed (2)"
echo "      Tests  4 passed (4)"
EOF
cat > scripts/dev.sh <<'EOF'
#!/bin/sh
echo "  VITE v5.2.0  ready in 312 ms"
echo ""
echo "  ➜  Local:   http://localhost:5173/"
while true; do sleep 1; done
EOF
chmod +x scripts/*.sh
git add -A && commit 0 "Ada Lovelace" "Add scripts"

# Uncommitted work for the git demos
cat >> src/store/cart.js <<'EOF'

export function clearCart() {
  items.length = 0
}
EOF
sed -i.bak 's/Add to cart/Add to cart ({{ product.price }})/' src/components/ProductCard.vue && rm src/components/ProductCard.vue.bak
cat > src/utils/discount.js <<'EOF'
export function applyDiscount(price, percent) {
  return Math.round(price * (100 - percent) / 100)
}
EOF

# ---------------------------------------------------------------- others
for name in api-server design-system blog dotfiles notes; do
  mkdir -p "$demo/projects/$name"
  echo "# $name" > "$demo/projects/$name/README.md"
  git -C "$demo/projects/$name" init -q -b main
done

cat > "$demo/config/project.add.vim" <<EOF
Project $demo/projects/webshop "online shop"
Project $demo/projects/api-server "REST API"
Project $demo/projects/design-system
Project $demo/projects/blog
Project $demo/projects/dotfiles
Project $demo/projects/notes
EOF

echo "Demo workspace ready: $demo"
