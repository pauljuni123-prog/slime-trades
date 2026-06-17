from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base
from app.routers import auth, mind_scan, ai_coach, guardian, mt5

app = FastAPI(title="Slime Trades API", version="0.1.0")

@app.get("/")
def root():
    return {"message": "Welcome to Slime Trades API"}


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

Base.metadata.create_all(bind=engine)

@app.get("/health")
def health_check():
    return {"status": "ok"}

app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(mind_scan.router, prefix="/mind-scans", tags=["Mind Scan"])
app.include_router(ai_coach.router, prefix="/ai", tags=["AI Coach"])
app.include_router(guardian.router, prefix="/guardian", tags=["Guardian"])
app.include_router(mt5.router, prefix="/mt5", tags=["MT5"])
