from faker import Faker
import uuid
import random
import json

fake = Faker()
NUM_VENDEURS = 20
NUM_PRODUITS = 400

# Génère pool de vendeurs (avec erreurs de qualité)
vendeurs = []
for i in range(NUM_VENDEURS):
    seller_id = str(uuid.uuid4())
    name = fake.company()
    category = random.choice(["Electronics", "Home", "Clothing", "Books", "Beauty"])
    status = random.choice(["active", "pending", "suspended"])

    # ---- Ajout d'erreurs potentielles ----
    if i % 7 == 0:  # un vendeur sur 7 : id manquant
        seller_id = "" if random.random() < 0.7 else None
    if i % 5 == 1:  # un vendeur sur 5 : nom vide
        name = ""
    if i % 10 == 2: # un vendeur sur 10 : statut inconnu
        status = "inactive"  # valeur inattendue
    
    vendeurs.append({
        "seller_id": seller_id,
        "name": name,
        "category": category,
        "status": status,
    })

# Génère produits, affectés aux vendeurs, avec erreurs
produits = []
for i in range(NUM_PRODUITS):
    vendeur = random.choice(vendeurs)
    produit_id = str(uuid.uuid4())
    name = fake.catch_phrase()
    unit_price = round(random.uniform(5, 300), 2)
    stock = random.randint(0, 500)
    category = vendeur["category"]

    # ---- Ajout d'erreurs potentielles ----
    if i % 11 == 0:      # produit sans id
        produit_id = "" if random.random() < 0.6 else None
    if i % 8 == 2:       # nom produit manquant
        name = ""
    if i % 13 == 3:      # prix au mauvais type
        unit_price = fake.word()
    if i % 19 == 5:      # stock négatif ou très grand (outlier)
        stock = random.choice([-1, -10, 10000])
    if i % 20 == 0:      # catégorie incohérente
        category = "Toys"

    produits.append({
        "product_id": produit_id,
        "seller_id": vendeur["seller_id"],
        "name": name,
        "category": category,
        "unit_price": unit_price,
        "stock": stock
    })

catalogue = {
    "sellers": vendeurs,
    "products": produits
}
with open("catalog.json", "w") as f:
    json.dump(catalogue, f, indent=2)