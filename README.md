# simple_wireguard

### 1. Clone this repo  
```
git clone https://github.com/finzzz/simple_wireguard.git
```

### 2. Navigate to the directory  
```
cd simple_wireguard
```
          
### 3. Make executable
```
chmod +x simple_wg.sh
```
         
### 4. Find network interface name (usually eth0)
```
ifconfig
```  
         
### 5. Run (as root)
```
./simple_wg.sh init eth0
```
***
### Add client
```
./simple_wg.sh add john 10.10.10.5
```
  
***
### Delete client
```
./simple_wg.sh del john
```

***
### List clients
```
./simple_wg.sh list
```
  
***
### Show client's QR code config
```
./simple_wg.sh qr john
```

***
### Use custom domain (during init)
```
./simple_wg.sh init eth0 mysite.com
```

