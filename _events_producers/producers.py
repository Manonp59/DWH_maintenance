from azure.eventhub import EventHubProducerClient, EventData
import json
import time
import random
import uuid
import os
from faker import Faker

# Initialize Faker
fake = Faker()

# On lit la connexion depuis une variable d'environnement
CONNECTION_STR = os.getenv("EVENTHUB_CONNECTION_STR")
ORDERS_INTERVAL      = int(os.getenv("ORDERS_INTERVAL", 60))
PRODUCTS_INTERVAL    = int(os.getenv("PRODUCTS_INTERVAL", 120))
CLICKSTREAM_INTERVAL = int(os.getenv("CLICKSTREAM_INTERVAL", 2))

if not CONNECTION_STR:
    raise RuntimeError("EVENTHUB_CONNECTION_STR n'est pas définie dans les variables d'environnement")

EVENT_HUBS = {
    "orders": ORDERS_INTERVAL,
    "clickstream": CLICKSTREAM_INTERVAL,
}

producers = {
    name: EventHubProducerClient.from_connection_string(CONNECTION_STR, eventhub_name=name)
    for name in EVENT_HUBS
}

timers = {name: 0 for name in EVENT_HUBS}

with open("catalog.json", "r") as f:
    master_catalog = json.load(f)

SELLERS_POOL = master_catalog["sellers"]
PRODUCTS_POOL = master_catalog["products"]

# Global pool of customers
CUSTOMERS_POOL = []
for _ in range(100):
    CUSTOMERS_POOL.append({
        "id": str(uuid.uuid4()),
        "name": fake.name(),
        "email": fake.email(),
        "address": fake.street_address(),
        "city": fake.city(),
        "country": fake.country()
    })


def build_event(name, now):
    if name == "orders":
        order_id = str(uuid.uuid4())
        items = []
        total_amount = 0
        num_items = random.randint(1, 5)
        # Select unique products to avoid duplicates in the same order
        selected_products = random.sample(PRODUCTS_POOL, num_items)
        
        for product in selected_products:
            qty = random.randint(1, 3)
            # On copie le produit pour ne pas modifier l'original dans le pool
            item = product.copy()
            item["quantity"] = qty
            items.append(item)
            total_amount += product["unit_price"] * qty
        
        # Pick a random customer from the pool
        customer = random.choice(CUSTOMERS_POOL)

        return {
            "event_id": str(uuid.uuid4()),
            "order_id": order_id,
            "customer": customer,
            "items": items,
            "total_amount": round(total_amount, 2),
            "currency": "USD",
            "status": "PLACED",
            "timestamp": now
        }

    if name == "clickstream":
        # Generate event type first
        event_type = random.choice(["view_page", "add_to_cart", "checkout_start"])
        
        # Set URL based on event type
        if event_type == "add_to_cart":
            url = "/cart"
        elif event_type == "checkout_start":
            url = "/checkout"
        else:  # view_page
            product = random.choice(PRODUCTS_POOL)
            url = random.choice([
                "/",
                "/login",
                f"/category/{product['category']}",
                f"/product/{product['product_id']}"
            ])
        
        return {
            "event_id": str(uuid.uuid4()),
            "session_id": str(uuid.uuid4()),
            "user_id": str(uuid.uuid4()) if (event_type == "checkout_start" or random.random() > 0.3) else None,
            "url": url,
            "event_type": event_type,
            "user_agent": fake.user_agent(),
            "ip_address": fake.ipv4(),
            "timestamp": now
        }

def safe_send(name, event):
    try:
        batch = producers[name].create_batch()
        batch.add(EventData(json.dumps(event)))
        producers[name].send_batch(batch)
        print(f"[{name}] Sent:", json.dumps(event, indent=2))
    except Exception as e:
        print("Erreur:", e)

if __name__ == "__main__":
    print("Multi-producer démarré dans le container.")

    while True:
        now = time.time()

        for name, interval in EVENT_HUBS.items():
            if now - timers[name] >= interval:
                event = build_event(name, now)
                safe_send(name, event)
                timers[name] = now

        time.sleep(0.5)