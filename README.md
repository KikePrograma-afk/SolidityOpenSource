# 🐾 Patitas Solidarias DAO - On-Chain Architecture


**Welcome to the heart of Patitas Solidarias DAO, a groundbreaking open-source project dedicated to revolutionizing the animal welfare space through radical transparency and community-driven governance.**

This repository contains the complete on-chain architecture, built on a modular, three-contract system designed for security, scalability, and true decentralization.

---

## 🔥 The Problem: The "Black Box" of Charity

The traditional donation model is broken. Billions are donated annually, yet a lack of transparency creates a "black box" where donors lose visibility of their impact. We believe that trust shouldn't be a requirement; it should be an outcome of verifiable proof.

## 🏗️ The "Holy Trinity" Architecture

To overcome the technical limitations of the EVM and build a robust ecosystem, our platform is powered by three interconnected smart contracts:

### 1. 📂 `ShelterDatabase.sol` — The Immutable Registry
- **Purpose:** To serve as the secure and efficient on-chain database for all shelter information.
- **Key Innovation:** Implements a "Progressive Registration Pattern" to handle vast amounts of data without hitting EVM stack or size limits.

### 2. 🧠 `MembershipAndVoting.sol` — The Democratic Brain
- **Purpose:** To manage the DAO's membership and a fair, secure voting system.
- **Key Innovation:** Solves the "chicken-and-egg" problem with a foundational membership model and features dynamic voting power.

### 3. 🏦 `DonationManager.sol` — The Transparent Treasury
- **Purpose:** To manage all financial flows with absolute transparency.
- **Key Innovation:** Manages direct donations only to DAO-approved shelters and includes a sustainable fee mechanism.

---

## 🚀 Project Status

- ✅ **Smart Contracts:** The full three-contract architecture is developed and deployed on the **Sonic Testnet** for public review.
- 🔧 **Frontend:** A user-friendly interface is currently under development using **React, TypeScript, Vite, and Tailwind CSS**.

## 🤝 How to Get Involved

This is a community-driven project. We invite you to be a part of this revolution.

-   **🔍 Audit the Code:** Review the contracts and open an `issue` if you find any vulnerabilities.
-   **🛠️ Contribute:** We welcome contributions. Check out our `issues` tab or propose your own ideas.
-   **📢 Spread the Word:** Share this project with developers and animal welfare advocates.

---

## ⚙️ Quick Start & Testing

To set up this project locally for testing:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/KikePrograma-afk/SolidityOpenSource.git
    ```
2.  **Install dependencies (e.g., Hardhat):**
    ```bash
    npm install
    ```
3.  **Compile the contracts:**
    ```bash
    npx hardhat compile
    ```

*(Note: Test files and a full Hardhat environment are currently under development).*

---

**Built with ❤️, 🧉, and a lot of cold nights from Catamarca, Argentina by Enrique Tillar.**