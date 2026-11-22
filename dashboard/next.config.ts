import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // O painel lê o banco a cada requisição, então o cache de componentes do Next 16
  // fica desligado: as rotas declaram o próprio comportamento com `dynamic`.
  cacheComponents: false,
  images: { remotePatterns: [{ protocol: "https", hostname: "images.unsplash.com" }] },
};

export default nextConfig;
