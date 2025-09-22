const CONTRACT_ADDRESS = 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM';
const CONTRACT_NAME = 'Anonymous-Voting';
const TESTNET = new StacksNetwork.TestnetNetwork();

class VotingApp {
    constructor() {
        this.userSession = null;
        this.userData = null;
        this.selectedPoll = null;
        this.selectedOption = null;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadPolls();
        this.checkWalletConnection();
    }

    setupEventListeners() {
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', () => this.switchTab(btn.dataset.tab));
        });

        document.getElementById('connect-wallet').addEventListener('click', () => this.connectWallet());
        document.getElementById('create-poll-form').addEventListener('submit', (e) => this.createPoll(e));
        document.getElementById('add-option').addEventListener('click', () => this.addOption());
        document.getElementById('load-results').addEventListener('click', () => this.loadResults());
        document.getElementById('register-voter').addEventListener('click', () => this.registerVoter());
        document.getElementById('check-registration').addEventListener('click', () => this.checkRegistration());
        document.getElementById('submit-vote').addEventListener('click', () => this.submitVote());

        document.querySelector('.close').addEventListener('click', () => this.closeModal());
        document.getElementById('vote-modal').addEventListener('click', (e) => {
            if (e.target.id === 'vote-modal') this.closeModal();
        });

        window.addEventListener('click', (e) => {
            if (e.target.classList.contains('modal')) {
                this.closeModal();
            }
        });
    }

    switchTab(tab) {
        document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
        
        document.querySelector(`[data-tab="${tab}"]`).classList.add('active');
        document.getElementById(`${tab}-tab`).classList.add('active');

        if (tab === 'vote') {
            this.loadPolls();
        }
    }

    async connectWallet() {
        try {
            const authOptions = {
                appDetails: {
                    name: 'Anonymous Voting System',
                    icon: window.location.origin + '/icon.png'
                },
                redirectTo: window.location.origin,
                onFinish: (authData) => {
                    this.userSession = authData.userSession;
                    this.userData = authData.userSession.loadUserData();
                    this.updateWalletStatus();
                    this.showToast('Wallet connected successfully!', 'success');
                }
            };

            await authenticate(authOptions);
        } catch (error) {
            console.error('Wallet connection failed:', error);
            this.showToast('Failed to connect wallet', 'error');
        }
    }

    checkWalletConnection() {
        if (window.userSession && window.userSession.isUserSignedIn()) {
            this.userSession = window.userSession;
            this.userData = this.userSession.loadUserData();
            this.updateWalletStatus();
        }
    }

    updateWalletStatus() {
        const statusEl = document.getElementById('wallet-status');
        const connectBtn = document.getElementById('connect-wallet');
        
        if (this.userData) {
            const address = this.userData.profile.stxAddress.testnet;
            statusEl.textContent = `Connected: ${address.slice(0, 6)}...${address.slice(-4)}`;
            connectBtn.textContent = 'Disconnect';
            connectBtn.onclick = () => this.disconnectWallet();
        } else {
            statusEl.textContent = 'Not Connected';
            connectBtn.textContent = 'Connect Wallet';
            connectBtn.onclick = () => this.connectWallet();
        }
    }

    disconnectWallet() {
        if (this.userSession) {
            this.userSession.signUserOut();
            this.userSession = null;
            this.userData = null;
            this.updateWalletStatus();
            this.showToast('Wallet disconnected', 'info');
        }
    }

    addOption() {
        const container = document.getElementById('options-container');
        const optionCount = container.querySelectorAll('.option-input').length;
        
        if (optionCount >= 10) {
            this.showToast('Maximum 10 options allowed', 'error');
            return;
        }

        const optionDiv = document.createElement('div');
        optionDiv.className = 'option-input';
        optionDiv.innerHTML = `
            <input type="text" class="option" placeholder="Option ${optionCount + 1}" maxlength="50" required>
            <button type="button" class="btn-remove" onclick="removeOption(this)">✕</button>
        `;
        container.appendChild(optionDiv);
    }

    async createPoll(e) {
        e.preventDefault();
        
        if (!this.userData) {
            this.showToast('Please connect your wallet first', 'error');
            return;
        }

        const title = document.getElementById('poll-title').value;
        const description = document.getElementById('poll-description').value;
        const duration = parseInt(document.getElementById('poll-duration').value);
        const options = Array.from(document.querySelectorAll('.option'))
            .map(input => input.value)
            .filter(value => value.trim() !== '');

        if (options.length < 2) {
            this.showToast('At least 2 options are required', 'error');
            return;
        }

        try {
            this.showLoading(true);
            
            const functionArgs = [
                stringAsciiCV(title),
                stringAsciiCV(description),
                listCV(options.map(opt => stringAsciiCV(opt))),
                uintCV(duration)
            ];

            const txOptions = {
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'create-poll',
                functionArgs: functionArgs,
                network: TESTNET,
                anchorMode: AnchorMode.Any,
                senderKey: this.userData.appPrivateKey,
                postConditionMode: PostConditionMode.Allow,
                onFinish: (data) => {
                    this.showLoading(false);
                    this.showToast('Poll created successfully!', 'success');
                    document.getElementById('create-poll-form').reset();
                    this.resetOptions();
                    this.switchTab('vote');
                    setTimeout(() => this.loadPolls(), 2000);
                },
                onCancel: () => {
                    this.showLoading(false);
                    this.showToast('Transaction cancelled', 'info');
                }
            };

            await makeContractCall(txOptions);
        } catch (error) {
            this.showLoading(false);
            console.error('Create poll error:', error);
            this.showToast('Failed to create poll', 'error');
        }
    }

    resetOptions() {
        const container = document.getElementById('options-container');
        container.innerHTML = `
            <div class="option-input">
                <input type="text" class="option" placeholder="Option 1" maxlength="50" required>
                <button type="button" class="btn-remove" onclick="removeOption(this)">✕</button>
            </div>
            <div class="option-input">
                <input type="text" class="option" placeholder="Option 2" maxlength="50" required>
                <button type="button" class="btn-remove" onclick="removeOption(this)">✕</button>
            </div>
        `;
    }

    async loadPolls() {
        try {
            const pollsContainer = document.getElementById('polls-list');
            const pollCount = await this.getPollCount();
            
            if (pollCount === 0) {
                pollsContainer.innerHTML = `
                    <div class="empty-state">
                        <p>No polls found</p>
                        <p>Create a new poll to get started</p>
                    </div>
                `;
                return;
            }

            const polls = [];
            for (let i = 1; i <= pollCount; i++) {
                const poll = await this.getPoll(i);
                if (poll) polls.push({id: i, ...poll});
            }

            const activePolls = polls.filter(poll => poll.isActive);
            
            if (activePolls.length === 0) {
                pollsContainer.innerHTML = `
                    <div class="empty-state">
                        <p>No active polls found</p>
                        <p>Create a new poll to get started</p>
                    </div>
                `;
                return;
            }

            pollsContainer.innerHTML = activePolls.map(poll => `
                <div class="poll-card" onclick="app.openVoteModal(${poll.id})">
                    <h3>${poll.title}</h3>
                    <p>${poll.description}</p>
                    <div class="poll-meta">
                        <span>Votes: ${poll.totalVotes}</span>
                        <span class="poll-status active">Active</span>
                    </div>
                </div>
            `).join('');
        } catch (error) {
            console.error('Load polls error:', error);
            this.showToast('Failed to load polls', 'error');
        }
    }

    async openVoteModal(pollId) {
        try {
            const poll = await this.getPoll(pollId);
            if (!poll) return;

            this.selectedPoll = pollId;
            document.getElementById('modal-poll-title').textContent = poll.title;
            document.getElementById('modal-poll-description').textContent = poll.description;
            
            const optionsContainer = document.getElementById('modal-options');
            optionsContainer.innerHTML = poll.options.map((option, index) => `
                <button class="vote-option" onclick="app.selectOption(${index})">${option}</button>
            `).join('');

            document.getElementById('vote-modal').style.display = 'block';
        } catch (error) {
            console.error('Open vote modal error:', error);
            this.showToast('Failed to load poll details', 'error');
        }
    }

    selectOption(index) {
        this.selectedOption = index;
        document.querySelectorAll('.vote-option').forEach(btn => btn.classList.remove('selected'));
        document.querySelectorAll('.vote-option')[index].classList.add('selected');
    }

    async submitVote() {
        if (!this.userData) {
            this.showToast('Please connect your wallet first', 'error');
            return;
        }

        if (this.selectedOption === null) {
            this.showToast('Please select an option', 'error');
            return;
        }

        try {
            this.showLoading(true);
            
            const voteType = document.querySelector('input[name="vote-type"]:checked').value;
            let functionName = 'cast-vote';
            let functionArgs = [uintCV(this.selectedPoll), uintCV(this.selectedOption)];

            if (voteType === 'anonymous') {
                functionName = 'cast-anonymous-vote';
                const nullifier = new Uint8Array(32);
                crypto.getRandomValues(nullifier);
                const proof = new Uint8Array(64);
                crypto.getRandomValues(proof);
                
                functionArgs = [
                    uintCV(this.selectedPoll),
                    uintCV(this.selectedOption),
                    bufferCV(nullifier),
                    bufferCV(proof)
                ];
            }

            const txOptions = {
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: functionName,
                functionArgs: functionArgs,
                network: TESTNET,
                anchorMode: AnchorMode.Any,
                senderKey: this.userData.appPrivateKey,
                postConditionMode: PostConditionMode.Allow,
                onFinish: (data) => {
                    this.showLoading(false);
                    this.showToast('Vote submitted successfully!', 'success');
                    this.closeModal();
                    this.loadPolls();
                },
                onCancel: () => {
                    this.showLoading(false);
                    this.showToast('Transaction cancelled', 'info');
                }
            };

            await makeContractCall(txOptions);
        } catch (error) {
            this.showLoading(false);
            console.error('Submit vote error:', error);
            this.showToast('Failed to submit vote', 'error');
        }
    }

    closeModal() {
        document.getElementById('vote-modal').style.display = 'none';
        this.selectedPoll = null;
        this.selectedOption = null;
        document.querySelectorAll('.vote-option').forEach(btn => btn.classList.remove('selected'));
    }

    async loadResults() {
        const pollId = parseInt(document.getElementById('results-poll-id').value);
        if (!pollId) {
            this.showToast('Please enter a poll ID', 'error');
            return;
        }

        try {
            const results = await this.getPollResults(pollId);
            if (!results) {
                this.showToast('Poll not found', 'error');
                return;
            }

            const container = document.getElementById('results-container');
            const maxVotes = Math.max(...results.votes);
            
            container.innerHTML = `
                <div class="results-header">
                    <h3>${results.title}</h3>
                    <p>Total Votes: ${results.totalVotes}</p>
                    <p>Status: ${results.isActive ? 'Active' : 'Ended'}</p>
                </div>
                <div class="results-list">
                    ${results.options.map((option, index) => `
                        <div class="result-item">
                            <h4>${option}</h4>
                            <div class="vote-bar">
                                <div class="vote-fill" style="width: ${maxVotes > 0 ? (results.votes[index] / maxVotes) * 100 : 0}%"></div>
                            </div>
                            <div class="vote-count">${results.votes[index]} votes (${maxVotes > 0 ? ((results.votes[index] / results.totalVotes) * 100).toFixed(1) : 0}%)</div>
                        </div>
                    `).join('')}
                </div>
            `;
        } catch (error) {
            console.error('Load results error:', error);
            this.showToast('Failed to load results', 'error');
        }
    }

    async registerVoter() {
        if (!this.userData) {
            this.showToast('Please connect your wallet first', 'error');
            return;
        }

        try {
            this.showLoading(true);
            
            const txOptions = {
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'register-voter',
                functionArgs: [],
                network: TESTNET,
                anchorMode: AnchorMode.Any,
                senderKey: this.userData.appPrivateKey,
                postConditionMode: PostConditionMode.Allow,
                onFinish: (data) => {
                    this.showLoading(false);
                    this.showToast('Registered successfully!', 'success');
                    setTimeout(() => this.checkRegistration(), 2000);
                },
                onCancel: () => {
                    this.showLoading(false);
                    this.showToast('Transaction cancelled', 'info');
                }
            };

            await makeContractCall(txOptions);
        } catch (error) {
            this.showLoading(false);
            console.error('Register voter error:', error);
            this.showToast('Failed to register', 'error');
        }
    }

    async checkRegistration() {
        if (!this.userData) {
            this.showToast('Please connect your wallet first', 'error');
            return;
        }

        try {
            const isRegistered = await this.isRegisteredVoter(this.userData.profile.stxAddress.testnet);
            const statusEl = document.getElementById('registration-status');
            const statusText = document.getElementById('reg-status-text');
            
            if (isRegistered) {
                statusEl.className = 'status-info registered';
                statusText.textContent = 'You are registered as a voter';
            } else {
                statusEl.className = 'status-info not-registered';
                statusText.textContent = 'You are not registered as a voter';
            }
        } catch (error) {
            console.error('Check registration error:', error);
            this.showToast('Failed to check registration', 'error');
        }
    }

    async getPollCount() {
        try {
            const response = await callReadOnlyFunction({
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'get-poll-count',
                functionArgs: [],
                network: TESTNET,
                senderAddress: this.userData?.profile?.stxAddress?.testnet || CONTRACT_ADDRESS
            });
            return parseInt(response);
        } catch (error) {
            console.error('Get poll count error:', error);
            return 0;
        }
    }

    async getPoll(pollId) {
        try {
            const response = await callReadOnlyFunction({
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'get-poll',
                functionArgs: [uintCV(pollId)],
                network: TESTNET,
                senderAddress: this.userData?.profile?.stxAddress?.testnet || CONTRACT_ADDRESS
            });
            
            if (response.type === 'some') {
                const poll = response.value;
                return {
                    title: poll.title,
                    description: poll.description,
                    options: poll.options,
                    totalVotes: parseInt(poll['total-votes']),
                    isActive: poll['is-active']
                };
            }
            return null;
        } catch (error) {
            console.error('Get poll error:', error);
            return null;
        }
    }

    async getPollResults(pollId) {
        try {
            const response = await callReadOnlyFunction({
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'get-poll-results',
                functionArgs: [uintCV(pollId)],
                network: TESTNET,
                senderAddress: this.userData?.profile?.stxAddress?.testnet || CONTRACT_ADDRESS
            });
            
            if (response.type === 'ok') {
                const results = response.value;
                return {
                    title: results.title,
                    options: results.options,
                    votes: results.votes.map(v => parseInt(v)),
                    totalVotes: parseInt(results['total-votes']),
                    isActive: results['is-active']
                };
            }
            return null;
        } catch (error) {
            console.error('Get poll results error:', error);
            return null;
        }
    }

    async isRegisteredVoter(address) {
        try {
            const response = await callReadOnlyFunction({
                contractAddress: CONTRACT_ADDRESS,
                contractName: CONTRACT_NAME,
                functionName: 'is-registered',
                functionArgs: [principalCV(address)],
                network: TESTNET,
                senderAddress: address
            });
            return response === true;
        } catch (error) {
            console.error('Is registered voter error:', error);
            return false;
        }
    }

    showLoading(show) {
        document.getElementById('loading').style.display = show ? 'flex' : 'none';
    }

    showToast(message, type = 'info') {
        const toast = document.getElementById('toast');
        toast.textContent = message;
        toast.className = `toast ${type} show`;
        
        setTimeout(() => {
            toast.classList.remove('show');
        }, 4000);
    }
}

function removeOption(button) {
    const container = document.getElementById('options-container');
    const optionInputs = container.querySelectorAll('.option-input');
    
    if (optionInputs.length > 2) {
        button.parentElement.remove();
    } else {
        app.showToast('At least 2 options are required', 'error');
    }
}

const { authenticate, showConnect, getStacksProvider } = StacksConnect;
const { StacksTestnet, StacksMainnet } = StacksNetwork;
const { makeContractCall, callReadOnlyFunction, AnchorMode, PostConditionMode } = StacksTransactions;
const { stringAsciiCV, uintCV, listCV, bufferCV, principalCV } = StacksTransactions;

const app = new VotingApp();
