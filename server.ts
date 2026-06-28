import express from "express";
import path from "path";
import { fileURLToPath } from "url";
import { createServer as createViteServer } from "vite";
import { GoogleGenAI, Type } from "@google/genai";
import dotenv from "dotenv";
import fs from "fs";
import nodemailer from "nodemailer";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json({ limit: "20mb" }));

  // Shared Gemini client lazy initializer
  let aiClient: GoogleGenAI | null = null;
  function getGeminiClient() {
    if (!aiClient) {
      const apiKey = process.env.GEMINI_API_KEY;
      if (!apiKey) {
        throw new Error("GEMINI_API_KEY environment variable is missing. Please set it in Settings > Secrets.");
      }
      aiClient = new GoogleGenAI({
        apiKey,
        httpOptions: {
          headers: {
            "User-Agent": "aistudio-build",
          },
        },
      });
    }
    return aiClient;
  }

  // API Route: Submit Waitlist
  app.post("/api/waitlist", async (req, res) => {
    try {
      const { name, email, city } = req.body;
      if (!email) {
        res.status(400).json({ error: "Email is required." });
        return;
      }

      // 1. Persist waitlist signups locally to a JSON file so leads are never lost
      const dataDir = path.join(process.cwd(), "data");
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
      const filePath = path.join(dataDir, "waitlist.json");
      let signups = [];
      if (fs.existsSync(filePath)) {
        try {
          signups = JSON.parse(fs.readFileSync(filePath, "utf-8"));
        } catch (e) {
          console.error("Error reading waitlist.json, resetting file:", e);
        }
      }

      const newSignup = {
        name: name || "Anonymous",
        email,
        city: city || "Not Specified",
        timestamp: new Date().toISOString(),
        queueNumber: signups.length + 385
      };

      signups.push(newSignup);
      fs.writeFileSync(filePath, JSON.stringify(signups, null, 2), "utf-8");

      // 2. Dispatch notification directly to Formspree to deliver to stooprene19@gmail.com
      const formspreeUrl = "https://formspree.io/f/mpqgrgzv";
      let emailSent = false;
      let emailErrorMsg = "";

      try {
        const response = await fetch(formspreeUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json"
          },
          body: JSON.stringify({
            name: newSignup.name,
            email: newSignup.email,
            city: newSignup.city,
            queueNumber: `#${newSignup.queueNumber}`,
            message: `🎉 New Blank.finder Lead!\n\nName: ${newSignup.name}\nEmail: ${newSignup.email}\nTarget Region: ${newSignup.city}\nQueue Position: #${newSignup.queueNumber}\n\nRegistered via Blank.finder Landing Page.`
          })
        });

        if (response.ok) {
          emailSent = true;
          console.log(`Successfully dispatched waitlist notification to Formspree for: ${email}`);
        } else {
          const errData = await response.json().catch(() => ({}));
          emailErrorMsg = errData.error || `Formspree returned status ${response.status}`;
          console.error(`Formspree submission failed:`, emailErrorMsg);
        }
      } catch (err: any) {
        console.error("Failed to post to Formspree:", err);
        emailErrorMsg = err.message || "Network error sending to Formspree";
      }

      res.json({
        success: true,
        queueNumber: newSignup.queueNumber,
        emailSent,
        error: emailSent ? null : emailErrorMsg
      });

    } catch (error: any) {
      console.error("Waitlist API handler error:", error);
      res.status(500).json({ error: error.message || "Internal server error" });
    }
  });

  // API Route: Generate Code
  app.post("/api/generate", async (req, res) => {
    try {
      const { prompt, files, chatHistory } = req.body;

      if (!prompt) {
        res.status(400).json({ error: "Prompt is required." });
        return;
      }

      const ai = getGeminiClient();

      // We form a structured instruction detailing files context
      const existingFilesSummary = Object.keys(files || {})
        .map((f) => `- ${f} (${files[f].length} chars)`)
        .join("\n");

      const systemInstruction = `You are a world-class senior AI software engineer and UI/UX designer. Your objective is to build complete, gorgeous, fully functional, and production-quality applications using React and Tailwind CSS.
Never return coming soon, placeholders, or mocked truncated parts. All components, forms, and elements must work perfectly.

You are being asked to create or modify code inside an interactive virtual workspace.
The existing workspace files are:
${existingFilesSummary}

Ensure the React code inside 'src/App.tsx' is completely self-contained or only references files you explicitly include in the files output.
Use Tailwind CSS classes directly for state changes, beautiful animations, shadows, layouts, and gradients.
You may use 'lucide-react' for icons and 'recharts' for any visual data representations.
Keep the style modern, highly polished, with elegant whitespace and dark slate or glassmorphism aesthetics.

Return a JSON object conforming exactly to this structure:
{
  "message": "Conversational markdown explanation of changes, design choices, and how to use the app.",
  "files": {
    "src/App.tsx": "Complete TSX React source code of the component...",
    "src/index.css": "Tailwind source code or custom global style overrides...",
    "src/data.ts": "Optionally generate static mock data or lists if relevant to keep code modular..."
  },
  "steps": [
    { "title": "Bootstrap layout configured", "status": "completed" },
    { "title": "Tailwind compiled", "status": "completed" },
    { "title": "Recharts visualizer integrated", "status": "completed" }
  ]
}`;

      // Build context from files & chat history
      const contents = [
        ...((chatHistory || []).map((msg: any) => ({
          role: msg.role === "assistant" ? "model" : "user",
          parts: [{ text: msg.content }],
        }))),
        {
          role: "user",
          parts: [
            {
              text: `Please fulfill this request: "${prompt}".
Here is the current content of the main app workspace files for reference:
${JSON.stringify(files, null, 2)}`
            }
          ]
        }
      ];

      const response = await ai.models.generateContent({
        model: "gemini-3.5-flash",
        contents,
        config: {
          systemInstruction,
          responseMimeType: "application/json",
          responseSchema: {
            type: Type.OBJECT,
            properties: {
              message: {
                type: Type.STRING,
                description: "Conversational markdown summary of what was generated, design choices, and features."
              },
              files: {
                type: Type.OBJECT,
                description: "Map of files to update or create in the virtual workspace.",
                additionalProperties: { type: Type.STRING }
              },
              steps: {
                type: Type.ARRAY,
                description: "Simulated compilation steps that completed during building.",
                items: {
                  type: Type.OBJECT,
                  properties: {
                    title: { type: Type.STRING },
                    status: { type: Type.STRING }
                  },
                  required: ["title", "status"]
                }
              }
            },
            required: ["message", "files", "steps"]
          }
        }
      });

      const responseText = response.text;
      if (!responseText) {
        throw new Error("No response returned from the Gemini model.");
      }

      const result = JSON.parse(responseText.trim());
      res.json(result);

    } catch (error: any) {
      console.error("Gemini Generation Error:", error);
      res.status(500).json({
        error: error.message || "Internal server error occurred while calling the Gemini API."
      });
    }
  });

  // Serve Vite in development, static files in production
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), "dist");
    app.use(express.static(distPath));
    app.get("*", (req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server started and listening on http://0.0.0.0:${PORT}`);
  });
}

startServer();
