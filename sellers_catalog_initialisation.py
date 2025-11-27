from faker import Faker
import uuid
import random
import json

fake = Faker()
NUM_VENDEURS = 20
NUM_PRODUITS = 400

# Génère pool de vendeurs
vendeurs = [{
    "seller_id": str(uuid.uuid4()),
    "name": fake.company(),
    "category": random.choice(["Electronics", "Home", "Clothing", "Books", "Beauty"]),
    "status": random.choice(["active", "pending", "suspended"]),
} for _ in range(NUM_VENDEURS)]

# Génère produits, affectés aux vendeurs
produits = []
for _ in range(NUM_PRODUITS):
    vendeur = random.choice(vendeurs)
    produit_id = str(uuid.uuid4())
    produits.append({
        "product_id": produit_id,
        "seller_id": vendeur["seller_id"],
        "name": fake.catch_phrase(),
        "category": vendeur["category"],
        "unit_price": round(random.uniform(5, 300), 2),
        "stock": random.randint(0, 500)
    })

# Exporte tout dans un JSON
catalogue = {
    "sellers": vendeurs,
    "products": produits
}
with open("catalog.json", "w") as f:
    json.dump(catalogue, f, indent=2)