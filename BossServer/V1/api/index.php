<?php
session_start();

// Session absichern
session_regenerate_id(true);               // Neue ID nach Login
ini_set('session.cookie_httponly', 1);     // JS kann Cookie nicht auslesen
ini_set('session.cookie_secure', 1);       // Nur über HTTPS (SSL nötig!)
ini_set('session.use_strict_mode', 1);     // Verhindert Session-Fishing

require 'verwaltung/users.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = $_POST['username'] ?? '';
    $pass = $_POST['password'] ?? '';

    if (isset($users[$user]) && password_verify($pass, $users[$user])) {
        $_SESSION['user'] = $user;
        header('Location: readflugbuch.php');
        exit;
    } else {
        $error = 'Falscher Benutzername oder Passwort!';
    }
}
?>


<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>Login - Flugdaten Auswertung</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }

        .login-box {
            background-color: #ffffff;
            padding: 30px 40px;
            border-radius: 12px;
            box-shadow: 0 8px 20px rgba(0,0,0,0.2);
            width: 100%;
            max-width: 400px;
        }

        .login-box h2 {
            text-align: center;
            color: #333;
            margin-bottom: 25px;
        }

        label {
            display: block;
            margin-bottom: 8px;
            font-weight: bold;
            color: #444;
        }

        input[type="text"],
        input[type="password"] {
            width: 100%;
            padding: 10px 12px;
            margin-bottom: 20px;
            border: 1px solid #ccc;
            border-radius: 8px;
            font-size: 14px;
        }

        button {
            width: 100%;
            background-color: #007bff;
            color: white;
            padding: 12px;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }

        button:hover {
            background-color: #0056b3;
        }

        .error {
            color: red;
            text-align: center;
            margin-top: 15px;
        }
    </style>
</head>
<body>

<div class="login-box">
    <h2>Login</h2>
    <form method="POST">
        <label for="username">Benutzername:</label>
        <input type="text" name="username" id="username" required>

        <label for="password">Passwort:</label>
        <input type="password" name="password" id="password" required>

        <button type="submit">Einloggen</button>
        
        <?php if (!empty($error)): ?>
            <p class="error"><?= htmlspecialchars($error) ?></p>
        <?php endif; ?>
    </form>
</div>

</body>
</html>
