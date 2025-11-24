# Mobile Preview Guide

To run the app and preview it on your mobile device connected to the same Wi-Fi network:

1.  **Find your PC's IP Address**:
    *   Open a terminal and run `ipconfig` (Windows) or `ifconfig` (Mac/Linux).
    *   Look for the IPv4 Address (e.g., `192.168.1.15`).

2.  **Run the App**:
    Run the following command in your terminal:
    ```bash
    flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
    ```

3.  **Access on Mobile**:
    *   Open your mobile browser (Chrome/Safari).
    *   Go to `http://YOUR_PC_IP:8080` (e.g., `http://192.168.1.15:8080`).

## Troubleshooting
*   **Firewall**: Ensure your PC's firewall allows incoming connections on port 8080.
*   **Same Network**: Ensure both your PC and mobile are on the same Wi-Fi network.
