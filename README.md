# 🔒 Anonymous Voting System

A zero-knowledge inspired anonymous voting system built on Stacks blockchain with Clarity smart contracts. Enable private, tamper-proof elections with complete voter anonymity.

## ✨ Features

- 🗳️ **Create Polls**: Set up custom polls with multiple options and duration
- 🔐 **Anonymous Voting**: Two voting modes - simple and enhanced anonymous
- 👥 **Voter Registration**: Secure voter registration system
- 📊 **Real-time Results**: View live poll results and statistics
- 🌐 **Responsive UI**: Works seamlessly on desktop and mobile
- ♿ **Accessible**: Full keyboard navigation and screen reader support
- 🔒 **Tamper-proof**: All votes stored immutably on blockchain

## 🚀 Quick Start

### Prerequisites

- Node.js 16+
- Clarinet CLI
- Stacks Wallet (Hiro Wallet recommended)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/anonymous-voting.git
   cd anonymous-voting
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Start Clarinet console**
   ```bash
   clarinet console
   ```

4. **Deploy the contract**
   ```bash
   clarinet deploy
   ```

5. **Serve the web interface**
   ```bash
   npx serve .
   ```

6. **Open in browser**
   Navigate to `http://localhost:3000`

## 🏗️ Architecture

### Smart Contract Functions

#### Public Functions
- `create-poll(title, description, options, duration)` - Create a new poll
- `register-voter()` - Register as an eligible voter
- `cast-vote(poll-id, option-index)` - Cast a simple vote
- `cast-anonymous-vote(poll-id, option-index, nullifier, proof)` - Cast anonymous vote
- `end-poll(poll-id)` - End a poll (creator/admin only)

#### Read-Only Functions
- `get-poll(poll-id)` - Get poll details
- `get-poll-results(poll-id)` - Get poll results
- `has-voted(poll-id, voter)` - Check if voter participated
- `is-registered(voter)` - Check voter registration status
- `get-poll-count()` - Get total number of polls

### Data Structures

```clarity
{
  title: string-ascii,
  description: string-ascii,
  creator: principal,
  start-block: uint,
  end-block: uint,
  options: (list 10 string-ascii),
  option-votes: (list 10 uint),
  total-votes: uint,
  is-active: bool,
  anonymous-key: buff
}
```

## 💻 Usage Guide

### 1. Connect Your Wallet
Click "Connect Wallet" and authorize the connection using your Stacks wallet.

### 2. Register as Voter
- Go to "Register" tab
- Click "Register as Voter"
- Confirm transaction in wallet

### 3. Create a Poll
- Navigate to "Create Poll" tab
- Fill in poll details:
  - **Title**: Brief poll description
  - **Description**: Detailed information
  - **Options**: 2-10 voting choices
  - **Duration**: Poll length in blocks (1440 ≈ 1 day)
- Submit and confirm transaction

### 4. Vote on Polls
- Visit "Vote" tab to see active polls
- Click on a poll to open voting modal
- Select your preferred option
- Choose voting method:
  - **Simple Vote**: Standard voting (less anonymous)
  - **Anonymous Vote**: Enhanced privacy protection
- Submit your vote

### 5. View Results
- Go to "Results" tab
- Enter poll ID to view results
- See real-time vote counts and percentages

## 🔐 Privacy Features

### Anonymous Voting Mechanism
- **Nullifier System**: Prevents double voting without revealing identity
- **Commitment Scheme**: Voters commit to choices without revealing them
- **Zero-Knowledge Inspired**: Uses cryptographic techniques for privacy

### Security Measures
- All votes immutably stored on blockchain
- Cryptographic nullifiers prevent manipulation
- Time-locked voting periods
- Voter registration system

## 🛠️ Development

### Project Structure
```
anonymous-voting/
├── contracts/
│   └── Anonymous-Voting.clar    # Smart contract
├── tests/
│   └── Anonymous-Voting_test.ts # Test suite
├── settings/
│   └── Devnet.toml             # Network settings
├── index.html                  # Web interface
├── styles.css                  # Styling
├── app.js                      # Frontend logic
└── README.md                   # Documentation
```

### Testing
```bash
# Run all tests
clarinet test

# Run specific test
clarinet test --filter test_create_poll

# Check contract syntax
clarinet check
```

### Deployment
```bash
# Deploy to devnet
clarinet deploy --network devnet

# Deploy to testnet
clarinet deploy --network testnet
```

## 📱 Web Interface

The web interface provides:
- **Responsive Design**: Works on all device sizes
- **Real-time Updates**: Live poll data and results
- **Wallet Integration**: Seamless Stacks wallet connection
- **Accessibility**: Full keyboard and screen reader support

### Browser Support
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## 🧪 Testing

### Unit Tests
```bash
# Run contract tests
clarinet test

# Test specific functions
clarinet test --filter create_poll
clarinet test --filter anonymous_vote
```

### Integration Tests
```bash
# Start local devnet
clarinet integrate

# Run integration suite
npm test
```

## 🔧 Configuration

### Network Settings
Edit `settings/Devnet.toml` to configure:
- Network endpoints
- Contract deployment settings
- Fee configurations

### Contract Parameters
Modify constants in `contracts/Anonymous-Voting.clar`:
- Maximum poll duration
- Vote option limits
- Error codes

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: Check this README and inline comments
- **Issues**: Report bugs via GitHub Issues
- **Discussions**: Join community discussions
- **Email**: Contact maintainers for support

## 🙏 Acknowledgments

- Stacks blockchain for secure smart contracts
- Clarity language for readable blockchain code
- Community contributors and testers
- Zero-knowledge cryptography research

## 📊 Stats

- **Contract Size**: 200+ lines of Clarity code
- **Web Interface**: Responsive HTML/CSS/JS
- **Test Coverage**: Comprehensive test suite
- **Security**: Audited voting mechanisms

---

Built with ❤️ for transparent, private, and secure voting systems.
