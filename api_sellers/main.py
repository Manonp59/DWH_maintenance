from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
import json
import random

app = FastAPI()

# Chargement du catalogue au démarrage
with open("catalog.json", "r") as f:
    master_catalog = json.load(f)

@app.get("/api/sellers")
def get_sellers():
    return master_catalog["sellers"]

@app.get("/api/products")
def get_products():
    products = master_catalog["products"]
    return products