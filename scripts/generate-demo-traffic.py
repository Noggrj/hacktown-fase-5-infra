#!/usr/bin/env python3
"""Gera tráfego real contra o stack local (docker-compose) pra popular o
dashboard "FIAP X — Serviços" do Grafana com dado de verdade antes de
gravar o vídeo de apresentação — não é tráfego fake direto no Prometheus,
é a aplicação real fazendo o trabalho real (cadastro, login, upload,
ffmpeg processando, e-mail sendo enviado).

Uso:
    python3 scripts/generate-demo-traffic.py
    python3 scripts/generate-demo-traffic.py --users 20 --videos 30

Pressupõe o stack local no ar (`cd local && docker compose up`) nas
portas padrão (Auth :8081, Video :8082).
"""

import argparse
import base64
import random
import sys
import time

import requests

AUTH_URL = "http://localhost:8081"
VIDEO_URL = "http://localhost:8082"

# Vídeo mp4 real e minúsculo (o mesmo usado nos testes manuais desta
# sessão) — curto o bastante pra processar em menos de 1s, real o
# bastante pra produzir frames de verdade via ffmpeg.
GOOD_VIDEO_B64 = "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"

FIRST_NAMES = [
    "ana", "bruno", "carla", "diego", "elisa", "felipe", "gabriela", "hugo",
    "isabela", "joao", "karina", "lucas", "mariana", "nicolas", "olivia",
    "pedro", "quenia", "rafael", "sofia", "thiago",
]


def log(msg: str) -> None:
    print(f"[demo] {msg}", flush=True)


def register(email: str, password: str) -> int:
    r = requests.post(f"{AUTH_URL}/auth/register", json={"email": email, "password": password}, timeout=10)
    return r.status_code


def login(email: str, password: str):
    r = requests.post(f"{AUTH_URL}/auth/login", json={"email": email, "password": password}, timeout=10)
    token = r.json().get("token") if r.status_code == 200 else None
    return r.status_code, token


def upload(token: str, filename: str, content: bytes) -> dict:
    files = {"video": (filename, content, "video/mp4")}
    r = requests.post(
        f"{VIDEO_URL}/videos", headers={"Authorization": f"Bearer {token}"}, files=files, timeout=30
    )
    r.raise_for_status()
    return r.json()


def jitter(lo: float, hi: float) -> None:
    time.sleep(random.uniform(lo, hi))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--users", type=int, default=12, help="quantos usuários cadastrar (default: 12)")
    parser.add_argument("--videos", type=int, default=20, help="quantos uploads no total (default: 20)")
    parser.add_argument(
        "--fail-rate", type=float, default=0.3, help="fração de uploads que devem falhar de propósito (default: 0.3)"
    )
    parser.add_argument(
        "--pace", type=float, default=1.2, help="segundos médios entre ações — maior = espalha mais no tempo (default: 1.2)"
    )
    args = parser.parse_args()

    try:
        requests.get(f"{AUTH_URL}/health", timeout=3)
        requests.get(f"{VIDEO_URL}/health", timeout=3)
    except requests.RequestException:
        log("ERRO: auth-service (:8081) ou video-service (:8082) não respondem.")
        log("Suba o stack antes: cd fiapx-infra/local && docker compose up")
        return 1

    good_video = base64.b64decode(GOOD_VIDEO_B64)
    bad_video = bytes(random.randint(0, 255) for _ in range(4096))  # nunca é um mp4 válido — sempre falha no ffmpeg

    tokens = []
    log(f"cadastrando {args.users} usuários...")
    for i in range(args.users):
        name = FIRST_NAMES[i % len(FIRST_NAMES)]
        email = f"{name}.demo{i}@fiapx.local"
        password = "supersecret123"

        status = register(email, password)
        if status not in (201, 409):
            log(f"  aviso: register {email} -> {status}")

        # ~85% loga certo de primeira, ~15% erra a senha antes de acertar
        # (gera fiapx_logins_total{result="invalid_credentials"} também,
        # não só "success").
        if random.random() < 0.15:
            login(email, "senha-errada-de-proposito")
            jitter(0.1, 0.4)

        status, token = login(email, password)
        if token:
            tokens.append((email, token))
        else:
            log(f"  aviso: login {email} -> {status}")

        jitter(args.pace * 0.3, args.pace * 0.7)

    log(f"{len(tokens)} usuários logados. subindo {args.videos} vídeos "
        f"(~{int(args.fail_rate * 100)}% de propósito inválidos)...")

    ok = fail = 0
    for i in range(args.videos):
        email, token = random.choice(tokens)
        is_bad = random.random() < args.fail_rate
        if is_bad:
            resp = upload(token, f"demo-invalido-{i:02d}.mp4", bad_video)
            fail += 1
        else:
            resp = upload(token, f"demo-video-{i:02d}.mp4", good_video)
            ok += 1
        log(f"  [{i + 1:02d}/{args.videos}] {email} enviou {resp['filename']} (id={resp['id'][:8]}...)")
        jitter(args.pace * 0.5, args.pace * 1.5)

    log(f"pronto: {ok} vídeos válidos + {fail} inválidos enviados.")
    log("o worker processa em segundo plano — dá uns 10-20s pra tudo baixar/processar/publicar/notificar.")
    log("abra http://localhost:3000/d/fiapx-services-overview pra ver os números.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
