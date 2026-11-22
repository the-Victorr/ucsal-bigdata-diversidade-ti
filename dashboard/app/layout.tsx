import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Funil TI · Raça, gênero e liderança na tecnologia brasileira",
  description:
    "Painel analítico sobre diversidade no setor de TI brasileiro, construído a partir da RAIS e do Novo CAGED. Projeto da disciplina de Big Data e Analytics, UCSAL 2026.2.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
